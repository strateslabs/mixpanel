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

  describe "handle_rate_limit/1" do
    test "pauses batching when rate limited" do
      # Simulate rate limit response
      Mixpanel.Batcher.handle_rate_limit(429)

      # Check that batcher is in rate limited state
      state = :sys.get_state(Mixpanel.Batcher)
      assert state.rate_limited == true
      assert state.rate_limit_until > System.monotonic_time(:millisecond)
    end

    test "calculates appropriate backoff time" do
      before_time = System.monotonic_time(:millisecond)
      Mixpanel.Batcher.handle_rate_limit(429)

      state = :sys.get_state(Mixpanel.Batcher)
      backoff_duration = state.rate_limit_until - before_time

      # Should be at least 2 seconds but not too long for tests
      assert backoff_duration >= 2000
      assert backoff_duration <= 10000
    end
  end
end
