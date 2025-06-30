defmodule Mixpanel.EventTest do
  use ExUnit.Case, async: true

  describe "new/2 for track events" do
    test "creates valid track event with required fields" do
      event = Mixpanel.Event.new("button_clicked", %{device_id: "device-uuid-123"})

      assert event.event == "button_clicked"
      assert event.properties == %{device_id: "device-uuid-123"}
      assert is_integer(event.time)
      assert event.time > 0
    end

    test "creates track event with properties" do
      event =
        Mixpanel.Event.new("button_clicked", %{
          device_id: "device-uuid-123",
          button_id: "submit",
          page: "checkout"
        })

      assert event.properties == %{
               device_id: "device-uuid-123",
               button_id: "submit",
               page: "checkout"
             }
    end

    test "creates track event with custom time" do
      custom_time = 1_234_567_890

      event =
        Mixpanel.Event.new("button_clicked", %{
          device_id: "device-uuid-123",
          time: custom_time
        })

      assert event.time == custom_time
    end

    test "creates track event with user_id for identified user" do
      event =
        Mixpanel.Event.new("login", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          method: "password"
        })

      assert event.properties == %{
               device_id: "device-uuid-123",
               user_id: "user@example.com",
               method: "password"
             }
    end

    test "creates track event with ip for geolocation" do
      event =
        Mixpanel.Event.new("page_view", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          ip: "192.168.1.1",
          page: "home"
        })

      assert event.properties == %{
               device_id: "device-uuid-123",
               user_id: "user@example.com",
               ip: "192.168.1.1",
               page: "home"
             }
    end

    test "raises when event name is missing" do
      assert_raise ArgumentError, "event name is required", fn ->
        Mixpanel.Event.new("", %{device_id: "device-uuid-123"})
      end
    end

    test "raises when device_id is missing" do
      assert_raise ArgumentError, "device_id is required", fn ->
        Mixpanel.Event.new("test_event", %{})
      end
    end
  end

  describe "new/1 for import events" do
    test "creates valid import event from map" do
      event_data = %{
        event: "signup",
        device_id: "device-uuid-123",
        time: 1_234_567_890,
        source: "organic"
      }

      event = Mixpanel.Event.new(event_data)

      assert event.event == "signup"
      assert event.time == 1_234_567_890

      assert event.properties == %{
               device_id: "device-uuid-123",
               source: "organic"
             }
    end

    test "uses current time when time is not provided" do
      event_data = %{
        event: "signup",
        device_id: "device-uuid-123"
      }

      event = Mixpanel.Event.new(event_data)

      assert is_integer(event.time)
      assert event.time > 0
    end

    test "raises when event field is missing" do
      assert_raise ArgumentError, "event name is required", fn ->
        Mixpanel.Event.new(%{device_id: "device-uuid-123"})
      end
    end
  end

  describe "validate/1" do
    test "validates successful event" do
      event = Mixpanel.Event.new("test_event", %{device_id: "device-uuid-123"})

      assert {:ok, ^event} = Mixpanel.Event.validate(event)
    end

    test "rejects event with empty name" do
      event = %Mixpanel.Event{
        event: "",
        properties: %{device_id: "device-uuid-123"},
        time: 1_234_567_890
      }

      assert {:error, "event name cannot be empty"} = Mixpanel.Event.validate(event)
    end

    test "rejects event with empty device_id" do
      event = %Mixpanel.Event{
        event: "test_event",
        properties: %{device_id: ""},
        time: 1_234_567_890
      }

      assert {:error, "device_id cannot be empty"} = Mixpanel.Event.validate(event)
    end

    test "rejects event that is too large" do
      large_properties = %{
        device_id: "device-uuid-123",
        # > 1MB
        data: String.duplicate("a", 1024 * 1024 + 1)
      }

      event = %Mixpanel.Event{
        event: "test_event",
        properties: large_properties,
        time: 1_234_567_890
      }

      assert {:error, "event size exceeds 1MB limit"} = Mixpanel.Event.validate(event)
    end

    test "rejects event with too many properties" do
      properties =
        for i <- 1..256, into: %{device_id: "device-uuid-123"}, do: {"prop_#{i}", "value"}

      event = %Mixpanel.Event{
        event: "test_event",
        properties: properties,
        time: 1_234_567_890
      }

      assert {:error, "event has too many properties (max 255)"} = Mixpanel.Event.validate(event)
    end

    test "rejects event with too deep nesting" do
      deep_properties = %{
        device_id: "device-uuid-123",
        level1: %{
          level2: %{
            level3: %{
              level4: "too deep"
            }
          }
        }
      }

      event = %Mixpanel.Event{
        event: "test_event",
        properties: deep_properties,
        time: 1_234_567_890
      }

      assert {:error, "properties nesting too deep (max 3 levels)"} =
               Mixpanel.Event.validate(event)
    end

    test "accepts event with valid nesting depth" do
      valid_properties = %{
        device_id: "device-uuid-123",
        level1: %{
          level2: %{
            level3: "ok"
          }
        }
      }

      event = %Mixpanel.Event{
        event: "test_event",
        properties: valid_properties,
        time: 1_234_567_890
      }

      assert {:ok, ^event} = Mixpanel.Event.validate(event)
    end
  end

  describe "to_track_payload/1" do
    test "creates proper track payload" do
      event =
        Mixpanel.Event.new("button_clicked", %{
          device_id: "device-uuid-123",
          button_id: "submit"
        })

      payload = Mixpanel.Event.to_track_payload(event)

      assert payload.event == "button_clicked"
      assert payload.properties["$device_id"] == "device-uuid-123"
      assert payload.properties.button_id == "submit"
      assert payload.properties.time == event.time
      # Will be set by client
      assert payload.properties.token == nil
    end

    test "converts identity properties to Mixpanel format" do
      event =
        Mixpanel.Event.new("login", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          ip: "192.168.1.1",
          method: "password"
        })

      payload = Mixpanel.Event.to_track_payload(event)

      assert payload.event == "login"
      assert payload.properties["$device_id"] == "device-uuid-123"
      assert payload.properties["$user_id"] == "user@example.com"
      assert payload.properties["ip"] == "192.168.1.1"
      assert payload.properties.method == "password"
      assert payload.properties.time == event.time
      # Will be set by client
      assert payload.properties.token == nil
    end
  end

  describe "to_import_payload/1" do
    test "creates proper import payload" do
      event =
        Mixpanel.Event.new("signup", %{
          device_id: "device-uuid-123",
          time: 1_234_567_890,
          source: "organic"
        })

      payload = Mixpanel.Event.to_import_payload(event)

      assert payload.event == "signup"
      assert payload.properties["$device_id"] == "device-uuid-123"
      assert payload.properties.time == 1_234_567_890
      assert payload.properties.source == "organic"
      # Will be set by client
      assert payload.properties.token == nil
    end

    test "converts identity properties to Mixpanel format for import" do
      event =
        Mixpanel.Event.new("purchase", %{
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          ip: "192.168.1.1",
          time: 1_234_567_890,
          amount: 99.99
        })

      payload = Mixpanel.Event.to_import_payload(event)

      assert payload.event == "purchase"
      assert payload.properties["$device_id"] == "device-uuid-123"
      assert payload.properties["$user_id"] == "user@example.com"
      assert payload.properties["ip"] == "192.168.1.1"
      assert payload.properties.time == 1_234_567_890
      assert payload.properties.amount == 99.99
      # Will be set by client
      assert payload.properties.token == nil
    end
  end

  describe "batch_validate/1" do
    test "validates list of events successfully" do
      events = [
        Mixpanel.Event.new("event1", %{device_id: "device-uuid-123"}),
        Mixpanel.Event.new("event2", %{device_id: "device-uuid-456"})
      ]

      assert {:ok, ^events} = Mixpanel.Event.batch_validate(events)
    end

    test "rejects batch with invalid event" do
      events = [
        Mixpanel.Event.new("event1", %{device_id: "device-uuid-123"}),
        %Mixpanel.Event{event: "", properties: %{device_id: "device-uuid-456"}, time: 123}
      ]

      assert {:error, "event name cannot be empty"} = Mixpanel.Event.batch_validate(events)
    end

    test "rejects empty batch" do
      assert {:error, "batch cannot be empty"} = Mixpanel.Event.batch_validate([])
    end

    test "rejects batch that is too large" do
      events = for i <- 1..2001, do: Mixpanel.Event.new("event", %{device_id: "device-uuid-#{i}"})

      assert {:error, "batch size exceeds maximum of 2000 events"} =
               Mixpanel.Event.batch_validate(events)
    end
  end
end
