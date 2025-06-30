defmodule Mixpanel.API.EventsTest do
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:mixpanel, :project_token, "test_token")

    on_exit(fn ->
      Application.delete_env(:mixpanel, :project_token)
    end)

    :ok
  end

  describe "track/2" do
    test "returns validation error for invalid event" do
      result = Mixpanel.API.Events.track("", %{device_id: "device-uuid-123"})

      assert {:error, "event name is required"} = result
    end
  end

  describe "track_many/1" do
    test "returns error for empty batch" do
      result = Mixpanel.API.Events.track_many([])

      assert {:error, "batch cannot be empty"} = result
    end

    test "returns error for batch that is too large" do
      large_batch = for i <- 1..2001, do: %{event: "test", device_id: "device-uuid-#{i}"}

      result = Mixpanel.API.Events.track_many(large_batch)

      assert {:error, "batch size exceeds maximum of 2000 events"} = result
    end

    test "returns error when service account is not configured" do
      Application.delete_env(:mixpanel, :service_account)

      events = [%{event: "test", device_id: "device-uuid-123"}]
      result = Mixpanel.API.Events.track_many(events)

      assert {:error, "service account not configured for import API"} = result
    end
  end
end
