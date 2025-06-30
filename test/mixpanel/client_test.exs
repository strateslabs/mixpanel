defmodule Mixpanel.ClientTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:mixpanel, :http_client, Mixpanel.HTTPClientMock)
    Application.put_env(:mixpanel, :project_token, "test_token")
    Application.put_env(:mixpanel, :base_url, "https://api.mixpanel.com")

    on_exit(fn ->
      Application.delete_env(:mixpanel, :http_client)
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :base_url)
    end)

    :ok
  end

  describe "track/2" do
    test "sends single event to track endpoint successfully" do
      event = %{
        event: "button_clicked",
        properties: %{
          "$device_id": "device-uuid-123",
          button_id: "submit"
        }
      }

      expect(Mixpanel.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://api.mixpanel.com/track"
        assert opts[:json] != nil
        assert opts[:headers] != nil
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.track([event], "test_token")
    end

    test "sends batch of events to track endpoint successfully" do
      events = [
        %{event: "event1", properties: %{distinct_id: "user1"}},
        %{event: "event2", properties: %{distinct_id: "user2"}}
      ]

      expect(Mixpanel.HTTPClientMock, :post, fn _url, opts ->
        payload = opts[:json]
        assert length(payload) == 2
        {:ok, %{status: 200, body: %{"status" => 1}}}
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.track(events, "test_token")
    end

    test "handles rate limit error with 429 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 429, body: "Rate limited"}}
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :rate_limit
      assert error.retryable? == true
    end

    test "handles validation error with 400 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "Invalid event"}}}
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :validation
      assert error.retryable? == false
    end

    test "handles auth error with 401 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :auth
      assert error.retryable? == false
    end

    test "handles server error with 500 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: "Server error"}}
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :server
      assert error.retryable? == true
    end

    test "handles network error" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :network
      assert error.retryable? == true
    end
  end

  describe "import/2" do
    test "sends events to import endpoint successfully" do
      events = [
        %{event: "signup", properties: %{distinct_id: "user123", time: 1_234_567_890}}
      ]

      service_account = %{
        username: "test_user",
        password: "test_pass",
        project_id: "123456"
      }

      expect(Mixpanel.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://api.mixpanel.com/import"
        assert opts[:json] != nil
        assert Enum.any?(opts[:headers], fn {key, _} -> key == "authorization" end)
        {:ok, %{status: 200, body: %{"num_records_imported" => 1}}}
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.import(events, service_account)
    end

    test "handles import-specific success response format" do
      events = [%{event: "test", properties: %{distinct_id: "user123"}}]
      service_account = %{username: "user", password: "pass", project_id: "123"}

      expect(Mixpanel.HTTPClientMock, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"num_records_imported" => 5}}}
      end)

      assert {:ok, %{accepted: 5}} = Mixpanel.Client.import(events, service_account)
    end
  end

end
