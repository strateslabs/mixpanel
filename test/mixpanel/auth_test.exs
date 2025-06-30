defmodule Mixpanel.AuthTest do
  use ExUnit.Case, async: true

  describe "track_headers/1" do
    test "returns headers with project token for track endpoint" do
      project_token = "test_token_123"

      headers = Mixpanel.Auth.track_headers(project_token)

      assert {"content-type", "application/json"} in headers
      assert {"accept", "application/json"} in headers
      # Token is added to payload, not headers for track endpoint
      refute Enum.any?(headers, fn {key, _} -> key == "authorization" end)
    end
  end

  describe "import_headers/1" do
    test "returns basic auth headers for import endpoint with service account" do
      service_account = %{
        username: "test_user",
        password: "test_pass",
        project_id: "123456"
      }

      headers = Mixpanel.Auth.import_headers(service_account)

      assert {"content-type", "application/json"} in headers
      assert {"accept", "application/json"} in headers

      # Should have basic auth header
      auth_header = Enum.find(headers, fn {key, _} -> key == "authorization" end)
      assert auth_header != nil
      {"authorization", auth_value} = auth_header
      assert String.starts_with?(auth_value, "Basic ")
    end

    test "returns correct basic auth encoding" do
      service_account = %{
        username: "test_user",
        password: "test_pass",
        project_id: "123456"
      }

      headers = Mixpanel.Auth.import_headers(service_account)

      {"authorization", auth_value} =
        Enum.find(headers, fn {key, _} -> key == "authorization" end)

      # Extract and decode the base64 part
      "Basic " <> encoded = auth_value
      decoded = Base.decode64!(encoded)

      assert decoded == "test_user:test_pass"
    end
  end

  describe "add_token_to_payload/2" do
    test "adds token to track event payload" do
      payload = %{
        event: "test_event",
        properties: %{
          "$device_id": "device-uuid-123",
          custom_prop: "value"
        }
      }

      result = Mixpanel.Auth.add_token_to_payload(payload, "test_token")

      assert result.properties.token == "test_token"
      assert result.properties."$device_id" == "device-uuid-123"
      assert result.properties.custom_prop == "value"
    end

    test "adds token to import event payload" do
      payload = %{
        event: "test_event",
        properties: %{
          "$device_id": "device-uuid-123",
          time: 1_234_567_890
        }
      }

      result = Mixpanel.Auth.add_token_to_payload(payload, "test_token")

      assert result.properties.token == "test_token"
      assert result.properties."$device_id" == "device-uuid-123"
      assert result.properties.time == 1_234_567_890
    end

    test "overwrites existing token in payload" do
      payload = %{
        event: "test_event",
        properties: %{
          "$device_id": "device-uuid-123",
          token: "old_token"
        }
      }

      result = Mixpanel.Auth.add_token_to_payload(payload, "new_token")

      assert result.properties.token == "new_token"
    end
  end

  describe "add_project_id_to_payload/2" do
    test "adds project_id to import event payload" do
      payload = %{
        event: "test_event",
        properties: %{
          "$device_id": "device-uuid-123"
        }
      }

      result = Mixpanel.Auth.add_project_id_to_payload(payload, "123456")

      assert result.properties.project_id == "123456"
      assert result.properties."$device_id" == "device-uuid-123"
    end
  end
end
