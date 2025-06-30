defmodule Mixpanel do
  @moduledoc """
  Elixir client for the Mixpanel API.

  This module provides a simple, idiomatic Elixir interface for tracking events
  and importing historical data to Mixpanel. It handles batching, rate limiting,
  and error recovery automatically.

  ## Configuration

      config :mixpanel,
        project_token: "your_project_token",
        service_account: %{
          username: "your_username",
          password: "your_password",
          project_id: "your_project_id"
        }

  ## Examples

      # Anonymous user tracking
      Mixpanel.track("page_view", %{
        device_id: "device-uuid-123",
        page: "/home"
      })

      # Identified user tracking
      Mixpanel.track("purchase", %{
        device_id: "device-uuid-123",
        user_id: "user@example.com",
        amount: 99.99
      })

      # Import historical events
      Mixpanel.import_events([
        %{event: "signup", device_id: "device-uuid-123", time: ~U[2023-01-01 00:00:00Z], source: "organic"},
        %{event: "purchase", device_id: "device-uuid-123", user_id: "user@example.com", time: ~U[2023-01-02 00:00:00Z], amount: 99.99}
      ])

      # Use batching for high-throughput scenarios
      Mixpanel.track("page_view", %{device_id: "device-uuid-123"}, batch: true)
      Mixpanel.flush()  # Flush pending batched events
  """

  alias Mixpanel.API

  @type response :: {:ok, map()} | {:error, String.t() | map()}
  @type properties :: map()

  @doc """
  Track a single event.

  ## Parameters

    * `event_name` - The name of the event to track
    * `properties` - Map containing event properties with required `:device_id`
    * `opts` - Optional keyword list of options

  ## Options

    * `:batch` - If true, add event to batch instead of sending immediately

  ## Examples

      # Anonymous user
      Mixpanel.track("page_view", %{
        device_id: "device-uuid-123",
        page: "/home"
      })

      # Identified user
      Mixpanel.track("purchase", %{
        device_id: "device-uuid-123",
        user_id: "user@example.com",
        amount: 99.99
      })

      # Add to batch
      Mixpanel.track("page_view", %{
        device_id: "device-uuid-123"
      }, batch: true)

  ## Returns

    * `{:ok, %{accepted: 1}}` - Event tracked successfully
    * `:ok` - Event added to batch (when `batch: true`)
    * `{:error, reason}` - Validation or API error
  """
  @spec track(String.t(), properties(), keyword()) :: response() | :ok
  def track(event_name, properties, opts \\ []) do
    case validate_track_inputs(event_name, properties) do
      :ok ->
        API.Events.track(event_name, properties, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Import a batch of historical events.

  Requires a service account to be configured for authentication.

  ## Parameters

    * `events` - List of event maps, each containing `:event`, `:device_id`, and optionally `:time`, `:user_id`, `:ip`, and other properties

  ## Examples

      events = [
        %{
          event: "signup",
          device_id: "device-uuid-123", 
          time: ~U[2023-01-01 00:00:00Z],
          source: "organic"
        },
        %{
          event: "first_purchase",
          device_id: "device-uuid-123",
          user_id: "user@example.com",
          time: ~U[2023-01-02 00:00:00Z], 
          amount: 49.99
        }
      ]

      Mixpanel.import_events(events)

  ## Returns

    * `{:ok, %{accepted: count}}` - Events imported successfully
    * `{:error, reason}` - Validation, configuration, or API error
  """
  @spec import_events([map()]) :: response()
  def import_events(events) when is_list(events) do
    case validate_import_inputs(events) do
      :ok ->
        API.Events.import(events)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def import_events(_events) do
    {:error, "events must be a list"}
  end

  @doc """
  Flush all pending batched events immediately.

  This forces any events that have been queued via `track/3` with `batch: true`
  to be sent to Mixpanel immediately, rather than waiting for the batch size
  or timeout to be reached.

  ## Examples

      # Add some events to batch
      Mixpanel.track("event1", %{device_id: "device-uuid-123"}, batch: true)
      Mixpanel.track("event2", %{device_id: "device-uuid-456"}, batch: true)

      # Force send now
      Mixpanel.flush()

  ## Returns

    * `:ok` - Flush completed (events may or may not have been sent successfully)
  """
  @spec flush() :: :ok
  def flush do
    Mixpanel.Batcher.flush()
  end

  # Private validation functions

  defp validate_track_inputs("", _properties) do
    {:error, "event name cannot be empty"}
  end

  defp validate_track_inputs(_event_name, properties) do
    if Map.has_key?(properties, :device_id) do
      :ok
    else
      {:error, "device_id is required"}
    end
  end

  defp validate_import_inputs([]) do
    {:error, "batch cannot be empty"}
  end

  defp validate_import_inputs(events) when is_list(events) do
    # Basic validation - detailed validation happens in API.Events
    case Enum.find(events, fn event ->
           not is_map(event) or not Map.has_key?(event, :event) or
             not Map.has_key?(event, :device_id)
         end) do
      nil -> :ok
      _invalid_event -> {:error, "all events must have :event and :device_id fields"}
    end
  end

  defp validate_import_inputs(_) do
    {:error, "events must be a list"}
  end
end
