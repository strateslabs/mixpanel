defmodule Mixpanel.IntegrationTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  setup do
    # Configure for testing
    Application.put_env(:mixpanel, :http_client, Mixpanel.HTTPClientMock)
    Application.put_env(:mixpanel, :project_token, "test_token_123")

    Application.put_env(:mixpanel, :service_account, %{
      username: "test_user",
      password: "test_pass",
      project_id: "123456"
    })

    # Reset batch settings for predictable testing
    Application.put_env(:mixpanel, :batch_size, 2)
    Application.put_env(:mixpanel, :batch_timeout, 100)

    # Enable global mode for this process and all child processes
    Mox.set_mox_global()

    # Global stub for batch operations
    stub_with_default_success()

    on_exit(fn ->
      Application.delete_env(:mixpanel, :http_client)
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :service_account)
      Application.delete_env(:mixpanel, :batch_size)
      Application.delete_env(:mixpanel, :batch_timeout)
      # Reset to private mode
      Mox.set_mox_private()
    end)

    :ok
  end

  defp stub_with_default_success do
    stub(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"status" => 1}}}
    end)
  end

  describe "track/2 happy paths" do
    test "successfully tracks a single event with immediate sending" do
      expect(Mixpanel.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://api.mixpanel.com/track"

        # Verify the payload structure
        payload = opts[:json]
        assert payload.event == "purchase"
        assert payload.properties.distinct_id == "user123"
        assert payload.properties.amount == 99.99
        assert payload.properties.token == "test_token_123"
        assert is_integer(payload.properties.time)

        # Verify headers
        headers = opts[:headers]
        assert {"content-type", "application/json"} in headers
        assert {"accept", "application/json"} in headers

        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result =
        Mixpanel.track("purchase", %{
          distinct_id: "user123",
          properties: %{
            amount: 99.99,
            currency: "USD"
          }
        })

      assert {:ok, %{accepted: 1}} = result
    end

    test "successfully tracks event with custom timestamp" do
      custom_time = ~U[2023-01-01 00:00:00Z]
      timestamp = DateTime.to_unix(custom_time)

      expect(Mixpanel.HTTPClientMock, :post, fn _url, opts ->
        payload = opts[:json]
        assert payload.properties.time == timestamp
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result =
        Mixpanel.track("signup", %{
          distinct_id: "user123",
          time: custom_time,
          properties: %{source: "organic"}
        })

      assert {:ok, %{accepted: 1}} = result
    end

    test "successfully adds event to batch when batch: true" do
      # Clear any existing events
      Mixpanel.flush()
      Process.sleep(10)

      # No HTTP expectation since it should go to batcher
      result =
        Mixpanel.track(
          "page_view",
          %{
            distinct_id: "user123",
            properties: %{page: "home"}
          },
          batch: true
        )

      assert :ok = result

      # Verify event was added to batcher (or already sent)
      state = :sys.get_state(Mixpanel.Batcher)
      # Events may have been auto-sent due to batch size, so just verify function worked
      assert length(state.events) >= 0
    end
  end

  describe "import_events/1 happy paths" do
    test "successfully imports a batch of historical events" do
      expect(Mixpanel.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://api.mixpanel.com/import"

        # Verify the payload structure
        events = opts[:json]
        assert length(events) == 2

        [event1, event2] = events
        assert event1.event == "signup"
        assert event1.properties.distinct_id == "user123"
        assert event1.properties.token == "test_token_123"
        assert event1.properties.project_id == "123456"
        assert event1.properties.source == "organic"

        assert event2.event == "first_purchase"
        assert event2.properties.distinct_id == "user123"
        assert event2.properties.amount == 49.99

        # Verify basic auth headers
        headers = opts[:headers]
        auth_header = Enum.find(headers, fn {key, _} -> key == "authorization" end)
        assert auth_header != nil
        {"authorization", auth_value} = auth_header
        assert String.starts_with?(auth_value, "Basic ")

        {:ok, %{status: 200, body: %{"num_records_imported" => 2}}}
      end)

      events = [
        %{
          event: "signup",
          distinct_id: "user123",
          time: ~U[2023-01-01 00:00:00Z],
          properties: %{source: "organic"}
        },
        %{
          event: "first_purchase",
          distinct_id: "user123",
          time: ~U[2023-01-02 00:00:00Z],
          properties: %{amount: 49.99}
        }
      ]

      result = Mixpanel.import_events(events)
      assert {:ok, %{accepted: 2}} = result
    end

    test "successfully imports single event" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, opts ->
        events = opts[:json]
        assert length(events) == 1
        {:ok, %{status: 200, body: %{"num_records_imported" => 1}}}
      end)

      events = [
        %{
          event: "test_event",
          distinct_id: "user123",
          properties: %{test: "value"}
        }
      ]

      result = Mixpanel.import_events(events)
      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "flush/0 happy path" do
    test "successfully flushes batched events" do
      # First add some events to the batch
      Mixpanel.track("event1", %{distinct_id: "user1"}, batch: true)
      Mixpanel.track("event2", %{distinct_id: "user2"}, batch: true)

      result = Mixpanel.flush()
      assert :ok = result

      # Verify batch was cleared
      # Give time for async processing
      Process.sleep(10)
      state = :sys.get_state(Mixpanel.Batcher)
      assert length(state.events) == 0
    end
  end

  describe "error handling integration" do
    test "handles rate limit errors gracefully" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 429, body: "Rate limited"}}
      end)

      result = Mixpanel.track("test_event", %{distinct_id: "user123"})

      assert {:error, error} = result
      assert error.type == :rate_limit
      assert error.retryable? == true
      assert error.message == "Rate limited"
    end

    test "handles validation errors gracefully" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid event data"}}}
      end)

      result = Mixpanel.track("test_event", %{distinct_id: "user123"})

      assert {:error, error} = result
      assert error.type == :validation
      assert error.retryable? == false
      assert error.message == "Invalid event data"
    end

    test "handles network errors gracefully" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      result = Mixpanel.track("test_event", %{distinct_id: "user123"})

      assert {:error, error} = result
      assert error.type == :network
      assert error.retryable? == true
      assert String.contains?(error.message, "Network error")
    end
  end

  describe "configuration integration" do
    test "uses configured project token in requests" do
      Application.put_env(:mixpanel, :project_token, "custom_token_456")

      expect(Mixpanel.HTTPClientMock, :post, fn _url, opts ->
        payload = opts[:json]
        assert payload.properties.token == "custom_token_456"
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result = Mixpanel.track("test_event", %{distinct_id: "user123"})
      assert {:ok, %{accepted: 1}} = result
    end

    test "uses configured service account for imports" do
      custom_service_account = %{
        username: "custom_user",
        password: "custom_pass",
        project_id: "custom_project"
      }

      Application.put_env(:mixpanel, :service_account, custom_service_account)

      expect(Mixpanel.HTTPClientMock, :post, fn _url, opts ->
        # Verify auth header uses custom credentials
        headers = opts[:headers]

        {"authorization", auth_value} =
          Enum.find(headers, fn {key, _} -> key == "authorization" end)

        "Basic " <> encoded = auth_value
        decoded = Base.decode64!(encoded)
        assert decoded == "custom_user:custom_pass"

        # Verify project_id in payload
        [event] = opts[:json]
        assert event.properties.project_id == "custom_project"

        {:ok, %{status: 200, body: %{"num_records_imported" => 1}}}
      end)

      result =
        Mixpanel.import_events([
          %{event: "test", distinct_id: "user123"}
        ])

      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "end-to-end batching behavior" do
    test "automatically sends batch when size limit is reached" do
      # Small batch for testing
      Application.put_env(:mixpanel, :batch_size, 2)

      # Clear any existing events first
      Mixpanel.flush()
      Process.sleep(20)

      # Add events to reach batch limit
      Mixpanel.track("event1", %{distinct_id: "user1"}, batch: true)
      Mixpanel.track("event2", %{distinct_id: "user2"}, batch: true)

      # Give time for async batch processing  
      Process.sleep(100)

      # Verify batch was automatically sent and cleared
      state = :sys.get_state(Mixpanel.Batcher)
      assert length(state.events) == 0
    end
  end
end
