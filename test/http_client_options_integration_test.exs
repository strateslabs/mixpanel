defmodule HTTPClientOptionsIntegrationTest do
  use ExUnit.Case

  setup do
    Application.put_env(:mixpanel, :project_token, "test_token")

    on_exit(fn ->
      Application.delete_env(:mixpanel, :http_client_options)
      Application.delete_env(:mixpanel, :project_token)
    end)

    :ok
  end

  test "users can disable retries completely" do
    # Configure to disable retries with Req.Test
    test_options = [
      plug: {Req.Test, __MODULE__},
      retry: false
    ]
    Application.put_env(:mixpanel, :http_client_options, test_options)

    # Stub to return rate limit error
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.resp(429, "Rate limited")
    end)

    result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

    assert {:error, error} = result
    assert error.type == :rate_limit
  end

  test "users can configure custom timeout values" do
    # Configure custom timeout with Req.Test
    test_options = [
      plug: {Req.Test, __MODULE__},
      receive_timeout: 30_000,
      retry: false  # Disable retries for fast test
    ]
    Application.put_env(:mixpanel, :http_client_options, test_options)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"status" => 1})
    end)

    result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

    assert {:ok, %{accepted: 1}} = result
  end

  test "users can override default retry settings" do
    # Configure custom retry settings with Req.Test
    test_options = [
      plug: {Req.Test, __MODULE__},
      retry: :safe_transient,  # Different retry strategy
      max_retries: 1,          # Fewer retries
      retry_log_level: :info   # Different log level
    ]
    Application.put_env(:mixpanel, :http_client_options, test_options)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"status" => 1})
    end)

    result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

    assert {:ok, %{accepted: 1}} = result
  end
  
  test "users can add additional Req options like error handling" do
    # Configure with additional options and Req.Test
    test_options = [
      plug: {Req.Test, __MODULE__},
      retry: false,
      decode_body: false  # Valid Req option
    ]
    Application.put_env(:mixpanel, :http_client_options, test_options)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"status" => 1})
    end)

    result = Mixpanel.track("test_event", %{device_id: "device-uuid-123"}, immediate: true)

    assert {:ok, %{accepted: 1}} = result
  end
end