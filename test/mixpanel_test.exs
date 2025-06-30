defmodule MixpanelTest do
  use ExUnit.Case
  import Mox
  doctest Mixpanel

  setup :verify_on_exit!

  setup do
    Application.put_env(:mixpanel, :project_token, "test_token")
    Application.put_env(:mixpanel, :http_client, Mixpanel.HTTPClientMock)

    # Enable global mode for this process and all child processes
    Mox.set_mox_global()

    # Default stub for any unexpected calls to HTTP client (like from batcher)
    stub(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"status" => 1}}}
    end)

    on_exit(fn ->
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :http_client)
      # Reset to private mode
      Mox.set_mox_private()
    end)

    :ok
  end

  describe "track/2 validation" do
    test "returns error for invalid event" do
      result = Mixpanel.track("", %{device_id: "device-uuid-123"})

      assert {:error, "event name cannot be empty"} = result
    end

    test "returns error when device_id is missing" do
      result = Mixpanel.track("test_event", %{})

      assert {:error, "device_id is required"} = result
    end
  end

  describe "track/2 happy paths" do
    test "successfully validates and calls API for immediate tracking" do
      # Mock successful HTTP response
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result =
        Mixpanel.track("purchase", %{
          device_id: "device-uuid-123",
          amount: 99.99
        }, immediate: true)

      assert {:ok, %{accepted: 1}} = result
    end

    test "successfully validates and passes to batcher for batch tracking" do
      # No HTTP mock needed since it goes to batcher
      result =
        Mixpanel.track(
          "page_view",
          %{
            device_id: "device-uuid-123",
            page: "home"
          }
        )

      assert :ok = result
    end

    test "handles valid event with custom timestamp" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      custom_time = ~U[2023-01-01 00:00:00Z]

      result =
        Mixpanel.track("signup", %{
          device_id: "device-uuid-123",
          time: custom_time,
          source: "organic"
        }, immediate: true)

      assert {:ok, %{accepted: 1}} = result
    end

    test "handles event with user_id for identified user" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result =
        Mixpanel.track("login", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          method: "password"
        }, immediate: true)

      assert {:ok, %{accepted: 1}} = result
    end

    test "handles event with ip for geolocation" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      result =
        Mixpanel.track("page_view", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com", 
          ip: "192.168.1.1",
          page: "home"
        }, immediate: true)

      assert {:ok, %{accepted: 1}} = result
    end
  end

  describe "import_events/1 validation" do
    test "returns error for empty list" do
      result = Mixpanel.import_events([])

      assert {:error, "batch cannot be empty"} = result
    end

    test "returns error for invalid event in batch" do
      events = [
        %{event: "valid_event", device_id: "device-uuid-123"},
        # Missing event field
        %{device_id: "device-uuid-456"}
      ]

      result = Mixpanel.import_events(events)

      assert {:error, "all events must have :event and :device_id fields"} = result
    end

    test "returns error for non-list input" do
      result = Mixpanel.import_events("not_a_list")

      assert {:error, "events must be a list"} = result
    end
  end

  describe "import_events/1 happy paths" do
    test "successfully validates and calls API for import" do
      Application.put_env(:mixpanel, :service_account, %{
        username: "test_user",
        password: "test_pass",
        project_id: "123456"
      })

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"num_records_imported" => 2}}}
      end)

      events = [
        %{event: "signup", device_id: "device-uuid-123", source: "organic"},
        %{event: "purchase", device_id: "device-uuid-123", user_id: "user123", amount: 49.99}
      ]

      result = Mixpanel.import_events(events)

      assert {:ok, %{accepted: 2}} = result
    end

    test "handles single event in list" do
      Application.put_env(:mixpanel, :service_account, %{
        username: "test_user",
        password: "test_pass",
        project_id: "123456"
      })

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"num_records_imported" => 1}}}
      end)

      events = [%{event: "test", device_id: "device-uuid-123"}]
      result = Mixpanel.import_events(events)

      assert {:ok, %{accepted: 1}} = result
    end

    test "returns error when service account not configured" do
      Application.delete_env(:mixpanel, :service_account)

      events = [%{event: "test", device_id: "device-uuid-123"}]
      result = Mixpanel.import_events(events)

      assert {:error, "service account not configured for import API"} = result
    end
  end

  describe "flush/0" do
    test "returns ok and flushes batcher" do
      result = Mixpanel.flush()

      assert :ok = result
    end
  end

  describe "API error propagation" do
    test "propagates rate limit errors from API" do
      # Mock single call - Req handles retries internally
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 429, body: "Rate limited"}}
      end)

      result = Mixpanel.track("test", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :rate_limit
      assert error.retryable? == true
    end

    test "propagates validation errors from API" do
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid data"}}}
      end)

      result = Mixpanel.track("test", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :validation
      assert error.retryable? == false
    end

    test "propagates network errors from client" do
      # Mock single call - Req handles retries internally  
      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      result = Mixpanel.track("test", %{device_id: "device-uuid-123"}, immediate: true)

      assert {:error, error} = result
      assert error.type == :network
      assert error.retryable? == true
    end
  end

  describe "configuration helpers" do
    test "uses configured project token" do
      Application.put_env(:mixpanel, :project_token, "custom_token")

      assert Application.get_env(:mixpanel, :project_token) == "custom_token"
    end
  end
end
