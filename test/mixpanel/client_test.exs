defmodule Mixpanel.ClientTest do
  use ExUnit.Case

  setup do
    Application.put_env(:mixpanel, :http_client, Mixpanel.TestHTTPClient)
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

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        assert conn.request_path == "/track"
        assert conn.method == "POST"

        assert List.keyfind(conn.req_headers, "content-type", 0) ==
                 {"content-type", "application/json"}

        Req.Test.json(conn, %{"status" => 1})
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.track([event], "test_token")
    end

    test "sends batch of events to track endpoint successfully" do
      events = [
        %{event: "event1", properties: %{distinct_id: "user1"}},
        %{event: "event2", properties: %{distinct_id: "user2"}}
      ]

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        # For now, let's just verify the request and return success
        # TODO: Figure out how to properly access the JSON body in Req.Test
        assert conn.request_path == "/track"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"status" => 1})
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.track(events, "test_token")
    end

    test "handles rate limit error with 429 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(429, "Rate limited")
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :rate_limit
      assert error.retryable? == true
    end

    test "handles validation error with 400 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "Invalid event"})
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :validation
      assert error.retryable? == false
    end

    test "handles auth error with 401 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(401, "Unauthorized")
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :auth
      assert error.retryable? == false
    end

    test "handles server error with 500 response" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(500, "Server error")
      end)

      assert {:error, error} = Mixpanel.Client.track([event], "test_token")
      assert error.type == :server
      assert error.retryable? == true
    end

    test "handles network error" do
      event = %{event: "test", properties: %{distinct_id: "user123"}}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        Req.Test.transport_error(conn, :timeout)
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

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        assert conn.request_path == "/import"
        assert conn.method == "POST"

        assert List.keyfind(conn.req_headers, "content-type", 0) ==
                 {"content-type", "application/json"}

        assert List.keyfind(conn.req_headers, "authorization", 0) != nil
        Req.Test.json(conn, %{"num_records_imported" => 1})
      end)

      assert {:ok, %{accepted: 1}} = Mixpanel.Client.import(events, service_account)
    end

    test "handles import-specific success response format" do
      events = [%{event: "test", properties: %{distinct_id: "user123"}}]
      service_account = %{username: "user", password: "pass", project_id: "123"}

      Req.Test.stub(Mixpanel.TestHTTPClient, fn conn ->
        Req.Test.json(conn, %{"num_records_imported" => 5})
      end)

      assert {:ok, %{accepted: 5}} = Mixpanel.Client.import(events, service_account)
    end
  end
end
