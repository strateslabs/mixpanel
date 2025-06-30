defmodule Mixpanel.IntegrationTest do
  use ExUnit.Case

  setup do
    # Configure for testing
    Application.put_env(:mixpanel, :project_token, "test_token_123")

    Application.put_env(:mixpanel, :service_account, %{
      username: "test_user",
      password: "test_pass",
      project_id: "123456"
    })

    # Reset batch settings for predictable testing
    Application.put_env(:mixpanel, :batch_size, 2)
    Application.put_env(:mixpanel, :batch_timeout, 100)

    # Configure Req.Test
    test_options = [
      plug: {Req.Test, __MODULE__},
      retry: false
    ]
    Application.put_env(:mixpanel, :http_client_options, test_options)

    # Global stub for batch operations
    stub_with_default_success()

    on_exit(fn ->
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :service_account)
      Application.delete_env(:mixpanel, :batch_size)
      Application.delete_env(:mixpanel, :batch_timeout)
      Application.delete_env(:mixpanel, :http_client_options)
    end)

    :ok
  end

  defp stub_with_default_success do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"status" => 1})
    end)

    allow_batcher_access()
  end

  defp allow_batcher_access do
    # Allow all processes to use the stub (needed for Batcher process)
    case Process.whereis(Mixpanel.Batcher) do
      nil -> :ignore
      pid -> Req.Test.allow(__MODULE__, self(), pid)
    end
  end

  describe "track/2 happy paths" do
    test "successfully tracks a single event with immediate sending" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/track"
        assert conn.method == "POST"

        # Verify headers
        assert List.keyfind(conn.req_headers, "content-type", 0) ==
                 {"content-type", "application/json"}

        assert List.keyfind(conn.req_headers, "accept", 0) == {"accept", "application/json"}

        # TODO: Add payload verification when we figure out how to access body

        Req.Test.json(conn, %{"status" => 1})
      end)

      result =
        Mixpanel.track(
          "purchase",
          %{
            device_id: "device-uuid-123",
            amount: 99.99,
            currency: "USD"
          },
          immediate: true
        )

      assert {:ok, %{accepted: 1}} = result
    end

    test "successfully validates and queues events for batching" do
      # No specific stub needed - uses default success stub

      result =
        Mixpanel.track("page_view", %{
          device_id: "device-uuid-123",
          page: "/home",
          referrer: "google.com"
        })

      assert :ok = result
    end

    test "handles events with all supported properties" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/track"
        Req.Test.json(conn, %{"status" => 1})
      end)

      custom_time = ~U[2023-01-01 12:00:00Z]

      result =
        Mixpanel.track(
          "signup",
          %{
            device_id: "device-uuid-123",
            user_id: "user@example.com",
            time: custom_time,
            ip: "192.168.1.1",
            source: "organic",
            campaign: "summer_sale"
          },
          immediate: true
        )

      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "track_many/1 happy paths" do
    test "successfully imports a batch of historical events" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/import"
        assert conn.method == "POST"

        # Verify headers include auth
        assert List.keyfind(conn.req_headers, "content-type", 0) ==
                 {"content-type", "application/json"}

        assert List.keyfind(conn.req_headers, "authorization", 0) != nil

        # TODO: Add payload verification when we figure out how to access body

        Req.Test.json(conn, %{"num_records_imported" => 2})
      end)

      events = [
        %{
          event: "signup",
          device_id: "device-uuid-123",
          time: ~U[2023-01-01 00:00:00Z],
          source: "organic",
          utm_campaign: "summer_sale"
        },
        %{
          event: "first_purchase",
          device_id: "device-uuid-123",
          time: ~U[2023-01-02 12:30:00Z],
          amount: 49.99,
          product: "starter_plan"
        }
      ]

      result = Mixpanel.track_many(events)

      assert {:ok, %{accepted: 2}} = result
    end

    test "successfully imports single event" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/import"
        assert conn.method == "POST"

        # Verify auth header
        {"authorization", auth_value} = List.keyfind(conn.req_headers, "authorization", 0)
        "Basic " <> encoded = auth_value
        decoded = Base.decode64!(encoded)
        assert decoded == "test_user:test_pass"

        Req.Test.json(conn, %{"num_records_imported" => 1})
      end)

      events = [
        %{
          event: "test_event",
          device_id: "device-uuid-123",
          time: ~U[2023-01-01 00:00:00Z]
        }
      ]

      result = Mixpanel.track_many(events)

      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "error handling integration" do
    test "handles rate limit errors gracefully" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(429, "Rate limited")
      end)

      result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :rate_limit
      assert error.retryable? == true
    end

    test "handles validation errors gracefully" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "Invalid event data"})
      end)

      result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :validation
      assert error.retryable? == false
    end

    test "handles network errors gracefully" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :network
      assert error.retryable? == true
    end
  end

  describe "configuration integration" do
    test "uses configured project token in requests" do
      # Custom token for this test
      Application.put_env(:mixpanel, :project_token, "custom_token_456")

      Req.Test.stub(__MODULE__, fn conn ->
        # TODO: Verify token is in request payload when we can access body
        Req.Test.json(conn, %{"status" => 1})
      end)

      result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:ok, %{accepted: 1}} = result
    end

    test "uses configured service account for imports" do
      # Custom service account for this test
      Application.put_env(:mixpanel, :service_account, %{
        username: "custom_user",
        password: "custom_pass",
        project_id: "custom_project"
      })

      Req.Test.stub(__MODULE__, fn conn ->
        # Verify auth header uses custom credentials
        {"authorization", auth_value} = List.keyfind(conn.req_headers, "authorization", 0)
        "Basic " <> encoded = auth_value
        decoded = Base.decode64!(encoded)
        assert decoded == "custom_user:custom_pass"

        # TODO: Add payload verification when we figure out how to access body

        Req.Test.json(conn, %{"num_records_imported" => 1})
      end)

      result =
        Mixpanel.track_many([
          %{event: "test", device_id: "device-uuid-123"}
        ])

      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "end-to-end batching behavior" do
    test "automatically sends batch when size limit is reached" do
      # Small batch for testing
      Application.put_env(:mixpanel, :batch_size, 2)

      # Ensure the batcher can use our stub
      allow_batcher_access()

      # Clear any existing events first
      Mixpanel.flush()
      Process.sleep(20)

      # Add events to reach batch limit
      Mixpanel.track("event1", %{device_id: "device-uuid-123"}, batch: true)
      Mixpanel.track("event2", %{device_id: "device-uuid-456"}, batch: true)

      # Give time for async batch processing  
      Process.sleep(100)

      # Verify batch was automatically sent and cleared
      state = :sys.get_state(Mixpanel.Batcher)
      assert length(state.events) == 0
    end
  end
end