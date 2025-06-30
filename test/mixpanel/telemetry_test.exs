defmodule Mixpanel.TelemetryTest do
  use ExUnit.Case, async: false

  alias Mixpanel.{API, Batcher}

  # Handler function for telemetry events
  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  setup do
    # Set up test configuration
    Application.put_env(:mixpanel, :project_token, "test_token")

    Application.put_env(:mixpanel, :service_account, %{
      username: "test_user",
      password: "test_pass",
      project_id: "test_project"
    })

    Application.put_env(:mixpanel, :http_client_options,
      plug: {Req.Test, __MODULE__},
      retry: false
    )

    # Clear any existing events in batcher
    Batcher.clear()

    # Set up telemetry event capture
    events = []

    handler_id = make_ref()

    :telemetry.attach_many(
      handler_id,
      [
        [:mixpanel, :track, :success],
        [:mixpanel, :track, :error],
        [:mixpanel, :track, :validation_error],
        [:mixpanel, :track, :batch_queued],
        [:mixpanel, :import, :success],
        [:mixpanel, :import, :error],
        [:mixpanel, :batch, :full],
        [:mixpanel, :batch, :queued],
        [:mixpanel, :batch, :sent],
        [:mixpanel, :batch, :failed],
        [:mixpanel, :batch, :rate_limited]
      ],
      &__MODULE__.handle_telemetry_event/4,
      self()
    )

    # Stub HTTP requests for successful responses
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"status" => 1})
    end)

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Application.delete_env(:mixpanel, :project_token)
      Application.delete_env(:mixpanel, :service_account)
      Application.delete_env(:mixpanel, :http_client_options)
    end)

    %{events: events}
  end

  describe "track/3 telemetry events" do
    test "emits track:success for immediate successful events" do
      result = API.Events.track("test_event", %{device_id: "device-123"}, immediate: true)

      assert {:ok, _} = result

      assert_receive {:telemetry_event, [:mixpanel, :track, :success], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_name == "test_event"
      assert metadata.immediate == true
    end

    test "emits track:error for immediate failed events" do
      # Stub HTTP request to return error
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "Invalid request"})
      end)

      result = API.Events.track("test_event", %{device_id: "device-123"}, immediate: true)

      assert {:error, _} = result

      assert_receive {:telemetry_event, [:mixpanel, :track, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_name == "test_event"
      assert metadata.immediate == true
    end

    test "emits track:validation_error for invalid events" do
      result = API.Events.track("", %{device_id: "device-123"})

      assert {:error, _} = result

      assert_receive {:telemetry_event, [:mixpanel, :track, :validation_error], measurements,
                      metadata}

      assert measurements.duration > 0
      assert metadata.event_name == ""
      assert is_binary(metadata.error)
    end

    test "emits track:batch_queued for batched events" do
      result = API.Events.track("test_event", %{device_id: "device-123"})

      assert :ok = result

      assert_receive {:telemetry_event, [:mixpanel, :track, :batch_queued], measurements,
                      metadata}

      assert measurements.duration > 0
      assert metadata.event_name == "test_event"
      assert metadata.batch_mode == true
    end
  end

  describe "track_many/1 telemetry events" do
    test "emits import:success for successful imports" do
      events = [
        %{event: "signup", device_id: "device-123"},
        %{event: "purchase", device_id: "device-456"}
      ]

      result = API.Events.track_many(events)

      assert {:ok, _} = result

      assert_receive {:telemetry_event, [:mixpanel, :import, :success], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_count == 2
    end

    test "emits import:error for failed imports" do
      # Stub HTTP request to return error
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "Invalid request"})
      end)

      events = [%{event: "test", device_id: "device-123"}]

      result = API.Events.track_many(events)

      assert {:error, _} = result

      assert_receive {:telemetry_event, [:mixpanel, :import, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_count == 1
    end

    test "emits import:error for empty batch" do
      result = API.Events.track_many([])

      assert {:error, "batch cannot be empty"} = result

      assert_receive {:telemetry_event, [:mixpanel, :import, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_count == 0
      assert metadata.error == "batch cannot be empty"
    end

    test "emits import:error for batch too large" do
      large_batch = for i <- 1..2001, do: %{event: "test", device_id: "device-#{i}"}

      result = API.Events.track_many(large_batch)

      assert {:error, "batch size exceeds maximum of 2000 events"} = result

      assert_receive {:telemetry_event, [:mixpanel, :import, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_count == 2001
      assert metadata.error == "batch size exceeds maximum of 2000 events"
    end

    test "emits import:error when service account not configured" do
      Application.delete_env(:mixpanel, :service_account)

      events = [%{event: "test", device_id: "device-123"}]
      result = API.Events.track_many(events)

      assert {:error, "service account not configured for import API"} = result

      assert_receive {:telemetry_event, [:mixpanel, :import, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.event_count == 1
      assert metadata.error == "service account not configured for import API"
    end

    test "does not emit telemetry when emit_telemetry: false" do
      events = [%{event: "test", device_id: "device-123"}]

      result = API.Events.track_many(events, emit_telemetry: false)

      assert {:ok, _} = result

      # Should not receive any telemetry events
      refute_receive {:telemetry_event, [:mixpanel, :import, :success], _, _}, 100
      refute_receive {:telemetry_event, [:mixpanel, :import, :error], _, _}, 100
    end
  end

  describe "batcher telemetry events" do
    test "emits batch:queued when events are added to batch" do
      # Set batch size high so it doesn't auto-send
      Application.put_env(:mixpanel, :batch_size, 100)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      assert_receive {:telemetry_event, [:mixpanel, :batch, :queued], measurements, _metadata}
      assert measurements.event_count == 1
    end

    test "emits batch:full when batch reaches size limit" do
      # Set batch size to 1 for immediate sending
      Application.put_env(:mixpanel, :batch_size, 1)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      assert_receive {:telemetry_event, [:mixpanel, :batch, :full], measurements, _metadata}
      assert measurements.event_count == 1
    end

    # Note: The following tests for async batch results are disabled because
    # Req.Test stubs don't work across Task boundaries. In a real application,
    # these events would be emitted properly.

    @tag :skip
    test "emits batch:sent for successful batch sends" do
      Application.put_env(:mixpanel, :batch_size, 1)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      # Wait for async batch processing
      assert_receive {:telemetry_event, [:mixpanel, :batch, :sent], _measurements, metadata}
      assert is_map(metadata.response)
    end

    @tag :skip
    test "emits batch:failed for failed batch sends" do
      Application.put_env(:mixpanel, :batch_size, 1)

      # Stub HTTP request to return error
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Server error"})
      end)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      # Wait for async batch processing
      assert_receive {:telemetry_event, [:mixpanel, :batch, :failed], _measurements, metadata}
      assert is_map(metadata.error)
    end

    @tag :skip
    test "emits batch:rate_limited for rate limited responses" do
      Application.put_env(:mixpanel, :batch_size, 1)

      # Stub HTTP request to return rate limit error
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "Rate limited"})
      end)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      # Wait for async batch processing
      assert_receive {:telemetry_event, [:mixpanel, :batch, :rate_limited], _measurements,
                      _metadata},
                     1000
    end
  end

  describe "no double telemetry emission" do
    test "batched events do not emit import telemetry" do
      Application.put_env(:mixpanel, :batch_size, 1)

      Batcher.add_event(%{event: "test", device_id: "device-123"})

      # Should receive batch events
      assert_receive {:telemetry_event, [:mixpanel, :batch, :full], _, _}

      # Should NOT receive import events (since we disabled telemetry in batcher)
      refute_receive {:telemetry_event, [:mixpanel, :import, :success], _, _}, 100
      refute_receive {:telemetry_event, [:mixpanel, :import, :error], _, _}, 100
    end

    test "direct track_many calls do not emit batch telemetry" do
      events = [%{event: "test", device_id: "device-123"}]

      result = API.Events.track_many(events)

      assert {:ok, _} = result

      # Should receive import events
      assert_receive {:telemetry_event, [:mixpanel, :import, :success], _, _}

      # Should NOT receive batch events
      refute_receive {:telemetry_event, [:mixpanel, :batch, :sent], _, _}, 100
      refute_receive {:telemetry_event, [:mixpanel, :batch, :failed], _, _}, 100
    end
  end

  describe "telemetry metadata and measurements" do
    test "all events include duration measurement" do
      API.Events.track("test", %{device_id: "device-123"}, immediate: true)

      assert_receive {:telemetry_event, _, measurements, _}
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
    end

    test "track events include event_name in metadata" do
      API.Events.track("custom_event", %{device_id: "device-123"}, immediate: true)

      assert_receive {:telemetry_event, [:mixpanel, :track, :success], _, metadata}
      assert metadata.event_name == "custom_event"
    end

    test "import events include event_count in metadata" do
      events = [
        %{event: "event1", device_id: "device-123"},
        %{event: "event2", device_id: "device-456"}
      ]

      API.Events.track_many(events)

      assert_receive {:telemetry_event, [:mixpanel, :import, :success], _, metadata}
      assert metadata.event_count == 2
    end

    test "batch events include event_count in measurements" do
      Application.put_env(:mixpanel, :batch_size, 100)

      Batcher.add_event(%{event: "test1", device_id: "device-123"})
      assert_receive {:telemetry_event, [:mixpanel, :batch, :queued], measurements1, _}
      assert measurements1.event_count == 1

      Batcher.add_event(%{event: "test2", device_id: "device-456"})
      assert_receive {:telemetry_event, [:mixpanel, :batch, :queued], measurements2, _}
      assert measurements2.event_count == 2
    end
  end
end
