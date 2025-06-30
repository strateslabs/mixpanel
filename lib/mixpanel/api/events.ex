defmodule Mixpanel.API.Events do
  @moduledoc """
  Events API endpoints for track and import operations.
  """

  alias Mixpanel.{Client, Config, Event}

  @type response :: {:ok, map()} | {:error, String.t() | map()}

  @spec track(String.t(), map()) :: response()
  def track(event_name, event_data, opts \\ []) do
    case create_and_validate_event(event_name, event_data) do
      {:ok, event} ->
        if Keyword.get(opts, :batch, false) do
          # Send to batcher instead of directly to client
          Mixpanel.Batcher.add_event(event)
          :ok
        else
          payload = Event.to_track_payload(event)
          project_token = Config.project_token()
          Client.track([payload], project_token)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec track_batch([map()]) :: response()
  def track_batch(events) do
    with {:ok, validated_events} <- validate_event_batch(events) do
      payloads = Enum.map(validated_events, &Event.to_track_payload/1)
      project_token = Config.project_token()
      Client.track(payloads, project_token)
    end
  end

  @spec import([map()]) :: response()
  def import(events) do
    case Config.service_account() do
      nil ->
        {:error, "service account not configured for import API"}

      service_account ->
        with {:ok, validated_events} <- validate_import_batch(events) do
          payloads = Enum.map(validated_events, &Event.to_import_payload/1)
          Client.import(payloads, service_account)
        end
    end
  end

  defp create_and_validate_event(event_name, event_data) do
    try do
      event = Event.new(event_name, event_data)
      Event.validate(event)
    rescue
      e in ArgumentError -> {:error, Exception.message(e)}
    end
  end

  defp validate_event_batch([]) do
    {:error, "batch cannot be empty"}
  end

  defp validate_event_batch(events) when length(events) > 2000 do
    {:error, "batch size exceeds maximum of 2000 events"}
  end

  defp validate_event_batch(events) do
    try do
      validated_events =
        Enum.map(events, fn event_or_data ->
          # Handle both Event structs and raw data maps
          event = 
            case event_or_data do
              %Event{} = event -> event
              event_data -> Event.new(event_data)
            end

          case Event.validate(event) do
            {:ok, validated_event} -> validated_event
            {:error, reason} -> throw({:validation_error, reason})
          end
        end)

      {:ok, validated_events}
    catch
      {:validation_error, reason} -> {:error, reason}
    end
  end

  defp validate_import_batch([]) do
    {:error, "batch cannot be empty"}
  end

  defp validate_import_batch(events) when length(events) > 2000 do
    {:error, "batch size exceeds maximum of 2000 events"}
  end

  defp validate_import_batch(events) do
    try do
      validated_events =
        Enum.map(events, fn event_data ->
          event = Event.new(event_data)

          case Event.validate(event) do
            {:ok, validated_event} -> validated_event
            {:error, reason} -> throw({:validation_error, reason})
          end
        end)

      {:ok, validated_events}
    catch
      {:validation_error, reason} -> {:error, reason}
    end
  end
end
