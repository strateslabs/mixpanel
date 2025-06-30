defmodule Mixpanel.API.Events do
  @moduledoc """
  Events API endpoints for track and import operations.
  """

  alias Mixpanel.{Client, Config, Event}
  require Logger

  @type response :: {:ok, map()} | {:error, String.t() | map()}

  @spec track(String.t(), map()) :: response()
  def track(event_name, event_data, opts \\ []) do
    start_time = System.monotonic_time()

    case create_and_validate_event(event_name, event_data) do
      {:ok, event} ->
        result =
          if Keyword.get(opts, :immediate, false) do
            # Send immediately instead of batching (Req handles retries automatically)
            payload = Event.to_track_payload(event)
            project_token = Config.project_token()

            Client.track([payload], project_token)
          else
            # Default behavior: add to batch
            Mixpanel.Batcher.add_event(event)

            emit_telemetry_event(:track, :batch_queued, start_time, %{
              event_name: event_name,
              batch_mode: true
            })

            :ok
          end

        case result do
          {:ok, response} ->
            emit_telemetry_event(:track, :success, start_time, %{
              event_name: event_name,
              immediate: Keyword.get(opts, :immediate, false),
              response: response
            })

            result

          {:error, reason} ->
            emit_telemetry_event(:track, :error, start_time, %{
              event_name: event_name,
              immediate: Keyword.get(opts, :immediate, false),
              error: reason
            })

            result

          :ok ->
            result
        end

      {:error, reason} ->
        emit_telemetry_event(:track, :validation_error, start_time, %{
          event_name: event_name,
          error: reason
        })

        {:error, reason}
    end
  end

  @spec track_batch([map()]) :: response()
  def track_batch(events) do
    start_time = System.monotonic_time()
    event_count = length(events)

    result =
      with {:ok, validated_events} <- validate_event_batch(events) do
        payloads = Enum.map(validated_events, &Event.to_track_payload/1)
        project_token = Config.project_token()

        Client.track(payloads, project_token)
      end

    case result do
      {:ok, response} ->
        emit_telemetry_event(:track_batch, :success, start_time, %{
          event_count: event_count,
          response: response
        })

        result

      {:error, reason} ->
        emit_telemetry_event(:track_batch, :error, start_time, %{
          event_count: event_count,
          error: reason
        })

        result
    end
  end

  @spec track_many([map()]) :: response()
  def track_many(events) do
    start_time = System.monotonic_time()
    event_count = length(events)

    result =
      case Config.service_account() do
        nil ->
          {:error, "service account not configured for import API"}

        service_account ->
          with {:ok, validated_events} <- validate_import_batch(events) do
            payloads = Enum.map(validated_events, &Event.to_import_payload/1)

            Client.track_many(payloads, service_account)
          end
      end

    case result do
      {:ok, response} ->
        emit_telemetry_event(:import, :success, start_time, %{
          event_count: event_count,
          response: response
        })

        result

      {:error, reason} ->
        emit_telemetry_event(:import, :error, start_time, %{
          event_count: event_count,
          error: reason
        })

        result
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

  defp emit_telemetry_event(operation, status, start_time, metadata) do
    end_time = System.monotonic_time()
    duration = end_time - start_time

    :telemetry.execute(
      [:mixpanel, operation, status],
      %{duration: duration},
      metadata
    )
  end
end
