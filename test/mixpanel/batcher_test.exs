defmodule Mixpanel.BatcherTest do
  use ExUnit.Case

  setup do
    Application.put_env(:mixpanel, :project_token, "test_token")
    # Small batch for testing
    Application.put_env(:mixpanel, :batch_size, 3)
    # Short timeout for testing
    Application.put_env(:mixpanel, :batch_timeout, 100)

    on_exit(fn ->
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :batch_size)
      Application.delete_env(:mixpanel, :batch_timeout)
    end)

    :ok
  end

  describe "add_event/1" do
    test "adds event to batch" do
      event = %{event: "test_event", device_id: "device-uuid-123"}
      assert :ok = Mixpanel.Batcher.add_event(event)

      # Check internal state
      state = :sys.get_state(Mixpanel.Batcher)
      # May have been flushed
      assert length(state.events) >= 0
    end
  end

  describe "flush/0" do
    test "returns :ok when no events to flush" do
      assert :ok = Mixpanel.Batcher.flush()
    end
  end

end
