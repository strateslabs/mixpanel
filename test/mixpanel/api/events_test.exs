defmodule Mixpanel.API.EventsTest do
  use ExUnit.Case

  setup do
    Application.put_env(:mixpanel, :project_token, "test_token")

    on_exit(fn ->
      Application.delete_env(:mixpanel, :project_token)
    end)

    :ok
  end

  describe "track/2" do
    test "returns validation error for invalid event" do
      result = Mixpanel.API.Events.track("", %{distinct_id: "user123"})

      assert {:error, "event name cannot be empty"} = result
    end
  end

  describe "track_batch/1" do
    test "returns error for empty batch" do
      result = Mixpanel.API.Events.track_batch([])

      assert {:error, "batch cannot be empty"} = result
    end

    test "returns error for batch that is too large" do
      large_batch = for i <- 1..2001, do: %{event: "test", distinct_id: "user#{i}"}

      result = Mixpanel.API.Events.track_batch(large_batch)

      assert {:error, "batch size exceeds maximum of 2000 events"} = result
    end
  end

  describe "import/1" do
    test "returns error when service account is not configured" do
      Application.delete_env(:mixpanel, :service_account)

      events = [%{event: "test", distinct_id: "user123"}]
      result = Mixpanel.API.Events.import(events)

      assert {:error, "service account not configured for import API"} = result
    end

    test "returns error for empty batch" do
      service_account = %{username: "user", password: "pass", project_id: "123"}
      Application.put_env(:mixpanel, :service_account, service_account)

      result = Mixpanel.API.Events.import([])

      assert {:error, "batch cannot be empty"} = result
    end
  end
end
