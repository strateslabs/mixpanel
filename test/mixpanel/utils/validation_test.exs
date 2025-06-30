defmodule Mixpanel.Utils.ValidationTest do
  use ExUnit.Case, async: true

  describe "validate_event_size/1" do
    test "accepts event under size limit" do
      event = %{event: "test", properties: %{small: "data"}}

      assert :ok = Mixpanel.Utils.Validation.validate_event_size(event)
    end

    test "rejects event over size limit" do
      # > 1MB
      large_data = String.duplicate("a", 1024 * 1024 + 1)
      event = %{event: "test", properties: %{large: large_data}}

      assert {:error, "event size exceeds 1MB limit"} =
               Mixpanel.Utils.Validation.validate_event_size(event)
    end
  end

  describe "validate_property_count/1" do
    test "accepts event with valid property count" do
      properties = for i <- 1..255, into: %{}, do: {"prop_#{i}", "value"}

      assert :ok = Mixpanel.Utils.Validation.validate_property_count(properties)
    end

    test "rejects event with too many properties" do
      properties = for i <- 1..256, into: %{}, do: {"prop_#{i}", "value"}

      assert {:error, "event has too many properties (max 255)"} =
               Mixpanel.Utils.Validation.validate_property_count(properties)
    end
  end

  describe "validate_nesting_depth/2" do
    test "accepts shallow nesting" do
      data = %{level1: "value"}

      assert :ok = Mixpanel.Utils.Validation.validate_nesting_depth(data, 3)
    end

    test "accepts maximum nesting depth" do
      data = %{level1: %{level2: %{level3: "value"}}}

      assert :ok = Mixpanel.Utils.Validation.validate_nesting_depth(data, 3)
    end

    test "rejects nesting that is too deep" do
      data = %{level1: %{level2: %{level3: %{level4: "value"}}}}

      assert {:error, "properties nesting too deep (max 3 levels)"} =
               Mixpanel.Utils.Validation.validate_nesting_depth(data, 3)
    end

    test "handles lists in nesting" do
      data = %{level1: [%{level2: %{level3: "value"}}]}

      assert :ok = Mixpanel.Utils.Validation.validate_nesting_depth(data, 3)
    end

    test "rejects deep nesting with lists" do
      data = %{level1: [%{level2: %{level3: %{level4: "value"}}}]}

      assert {:error, "properties nesting too deep (max 3 levels)"} =
               Mixpanel.Utils.Validation.validate_nesting_depth(data, 3)
    end
  end

  describe "validate_required_fields/2" do
    test "accepts data with all required fields" do
      data = %{event: "test", device_id: "device-uuid-123"}
      required = [:event, :device_id]

      assert :ok = Mixpanel.Utils.Validation.validate_required_fields(data, required)
    end

    test "rejects data missing required field" do
      data = %{event: "test"}
      required = [:event, :device_id]

      assert {:error, "device_id is required"} =
               Mixpanel.Utils.Validation.validate_required_fields(data, required)
    end

    test "rejects data with empty required field" do
      data = %{event: "", device_id: "device-uuid-123"}
      required = [:event, :device_id]

      assert {:error, "event cannot be empty"} =
               Mixpanel.Utils.Validation.validate_required_fields(data, required)
    end
  end
end
