defmodule Mixpanel.Event do
  @moduledoc """
  Event struct and validation for Mixpanel events.
  """

  alias Mixpanel.Utils.Validation

  @type t :: %__MODULE__{
          event: String.t(),
          distinct_id: String.t(),
          properties: map(),
          time: integer()
        }

  defstruct [:event, :distinct_id, :properties, :time]

  @spec new(String.t(), map()) :: t()
  def new("", _event_data) do
    raise ArgumentError, "event name is required"
  end

  def new(_event_name, event_data) when not is_map_key(event_data, :distinct_id) do
    raise ArgumentError, "distinct_id is required"
  end

  def new(event_name, %{distinct_id: distinct_id} = event_data) do
    properties = Map.get(event_data, :properties, %{})
    time = normalize_time(Map.get(event_data, :time, current_timestamp()))

    %__MODULE__{
      event: event_name,
      distinct_id: distinct_id,
      properties: properties,
      time: time
    }
  end

  @spec new(map()) :: t()
  def new(%{event: event_name, distinct_id: distinct_id} = event_data) do
    properties = Map.get(event_data, :properties, %{})
    time = normalize_time(Map.get(event_data, :time, current_timestamp()))

    %__MODULE__{
      event: event_name,
      distinct_id: distinct_id,
      properties: properties,
      time: time
    }
  end

  def new(%{event: ""}) do
    raise ArgumentError, "event name is required"
  end

  def new(event_data) when not is_map_key(event_data, :event) do
    raise ArgumentError, "event name is required"
  end

  def new(event_data) when not is_map_key(event_data, :distinct_id) do
    raise ArgumentError, "distinct_id is required"
  end

  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = event) do
    with :ok <- validate_event_name(event.event),
         :ok <- validate_distinct_id(event.distinct_id),
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
        Map.merge(event.properties, %{
          distinct_id: event.distinct_id,
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
        Map.merge(event.properties, %{
          distinct_id: event.distinct_id,
          time: event.time,
          # Will be set by auth module
          token: nil
        })
    }
  end

  defp validate_event_name(""), do: {:error, "event name cannot be empty"}
  defp validate_event_name(name) when is_binary(name), do: :ok
  defp validate_event_name(_), do: {:error, "event name must be a string"}

  defp validate_distinct_id(""), do: {:error, "distinct_id cannot be empty"}
  defp validate_distinct_id(id) when is_binary(id), do: :ok
  defp validate_distinct_id(_), do: {:error, "distinct_id must be a string"}

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
