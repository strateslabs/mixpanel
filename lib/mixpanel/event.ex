defmodule Mixpanel.Event do
  @moduledoc """
  Event struct and validation for Mixpanel events.
  """

  alias Mixpanel.Utils.Validation

  @type t :: %__MODULE__{
          event: String.t(),
          properties: map(),
          time: integer()
        }

  defstruct [:event, :properties, :time]

  @spec new(String.t(), map()) :: t()
  def new("", _properties) do
    raise ArgumentError, "event name is required"
  end

  def new(_event_name, properties) when not is_map_key(properties, :device_id) do
    raise ArgumentError, "device_id is required"
  end

  def new(event_name, properties) when is_map(properties) do
    time = normalize_time(Map.get(properties, :time, current_timestamp()))
    # Remove time from properties since it's stored separately
    final_properties = Map.delete(properties, :time)

    %__MODULE__{
      event: event_name,
      properties: final_properties,
      time: time
    }
  end

  @spec new(map()) :: t()
  def new(%{event: event_name} = event_data) when is_binary(event_name) and event_name != "" do
    # Separate event name from the rest of the properties
    properties = Map.delete(event_data, :event)

    # Check for required device_id
    unless Map.has_key?(properties, :device_id) do
      raise ArgumentError, "device_id is required"
    end

    time = normalize_time(Map.get(properties, :time, current_timestamp()))
    # Remove time from properties since it's stored separately
    final_properties = Map.delete(properties, :time)

    %__MODULE__{
      event: event_name,
      properties: final_properties,
      time: time
    }
  end

  def new(%{event: ""}) do
    raise ArgumentError, "event name is required"
  end

  def new(event_data) when not is_map_key(event_data, :event) do
    raise ArgumentError, "event name is required"
  end

  def new(event_data) when not is_map_key(event_data, :device_id) do
    raise ArgumentError, "device_id is required"
  end

  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = event) do
    with :ok <- validate_event_name(event.event),
         :ok <- validate_device_id(Map.get(event.properties, :device_id)),
         :ok <- validate_optional_user_id(Map.get(event.properties, :user_id)),
         :ok <- validate_optional_ip(Map.get(event.properties, :ip)),
         :ok <- Validation.validate_event_size(event),
         :ok <- Validation.validate_property_count(event.properties),
         :ok <- Validation.validate_nesting_depth(event.properties, 3) do
      {:ok, event}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec batch_validate([t()]) :: {:ok, [t()]} | {:error, String.t()}
  def batch_validate([]) do
    {:error, "batch cannot be empty"}
  end

  def batch_validate(events) when length(events) > 2000 do
    {:error, "batch size exceeds maximum of 2000 events"}
  end

  def batch_validate(events) do
    case Enum.reduce_while(events, [], fn event, acc ->
           case validate(event) do
             {:ok, validated_event} -> {:cont, [validated_event | acc]}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      {:error, reason} -> {:error, reason}
      validated_events -> {:ok, Enum.reverse(validated_events)}
    end
  end

  @spec to_track_payload(t()) :: map()
  def to_track_payload(%__MODULE__{} = event) do
    %{
      event: event.event,
      properties:
        event.properties
        |> convert_identity_properties()
        |> Map.merge(%{
          time: event.time,
          # Will be set by auth module
          token: nil
        })
    }
  end

  @spec to_import_payload(t()) :: map()
  def to_import_payload(%__MODULE__{} = event) do
    %{
      event: event.event,
      properties:
        event.properties
        |> convert_identity_properties()
        |> Map.merge(%{
          time: event.time,
          # Will be set by auth module
          token: nil
        })
    }
  end

  defp validate_event_name(""), do: {:error, "event name cannot be empty"}
  defp validate_event_name(name) when is_binary(name), do: :ok
  defp validate_event_name(_), do: {:error, "event name must be a string"}

  defp validate_device_id(nil), do: {:error, "device_id is required"}
  defp validate_device_id(""), do: {:error, "device_id cannot be empty"}
  defp validate_device_id(id) when is_binary(id), do: :ok
  defp validate_device_id(_), do: {:error, "device_id must be a string"}

  defp validate_optional_user_id(nil), do: :ok
  defp validate_optional_user_id(""), do: {:error, "user_id cannot be empty when present"}
  defp validate_optional_user_id(id) when is_binary(id), do: :ok
  defp validate_optional_user_id(_), do: {:error, "user_id must be a string"}

  defp validate_optional_ip(nil), do: :ok
  defp validate_optional_ip(""), do: {:error, "ip cannot be empty when present"}
  defp validate_optional_ip(ip) when is_binary(ip), do: :ok
  defp validate_optional_ip(_), do: {:error, "ip must be a string"}

  defp convert_identity_properties(properties) do
    properties
    |> convert_property(:device_id, "$device_id")
    |> convert_property(:user_id, "$user_id")
    |> convert_property(:ip, "ip")
  end

  defp convert_property(properties, from_key, to_key) do
    case Map.get(properties, from_key) do
      nil ->
        properties

      value ->
        properties
        |> Map.delete(from_key)
        |> Map.put(to_key, value)
    end
  end

  defp current_timestamp do
    System.system_time(:second)
  end

  defp normalize_time(%DateTime{} = datetime) do
    DateTime.to_unix(datetime)
  end

  defp normalize_time(timestamp) when is_integer(timestamp) do
    timestamp
  end

  defp normalize_time(_) do
    current_timestamp()
  end
end
