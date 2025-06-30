defmodule Mixpanel.Batcher do
  @moduledoc """
  GenServer for batching events before sending to Mixpanel.
  """

  use GenServer
  alias Mixpanel.{API, Config, Event}
  require Logger

  @type state :: %{
          events: [Event.t()],
          timer_ref: reference() | nil,
          rate_limited: boolean(),
          rate_limit_until: integer()
        }

  # Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_event(Event.t() | map()) :: :ok
  def add_event(event) do
    GenServer.cast(__MODULE__, {:add_event, event})
  end

  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @spec handle_rate_limit(pos_integer()) :: :ok
  def handle_rate_limit(status_code) when status_code == 429 do
    GenServer.cast(__MODULE__, {:rate_limit, System.monotonic_time(:millisecond)})
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{
      events: [],
      timer_ref: nil,
      rate_limited: false,
      rate_limit_until: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add_event, event_data}, state) do
    if rate_limited?(state) do
      # Drop event if we're rate limited (could queue for later in post-MVP)
      Logger.warning("Dropping event due to rate limiting")
      {:noreply, state}
    else
      event = ensure_event_struct(event_data)
      new_events = [event | state.events]

      state = %{state | events: new_events}

      if should_send_batch?(new_events) do
        send_batch_async(new_events)
        :telemetry.execute([:mixpanel, :batch, :full], %{event_count: length(new_events)}, %{})
        state = reset_batch_state(state)
        {:noreply, state}
      else
        :telemetry.execute([:mixpanel, :batch, :queued], %{event_count: length(new_events)}, %{})
        state = ensure_timer_running(state)
        {:noreply, state}
      end
    end
  end

  @impl GenServer
  def handle_cast({:rate_limit, timestamp}, state) do
    backoff_duration = calculate_rate_limit_backoff()
    rate_limit_until = timestamp + backoff_duration

    Logger.warning("Rate limited, backing off for #{backoff_duration}ms")

    state = %{
      state
      | rate_limited: true,
        rate_limit_until: rate_limit_until
    }

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    if length(state.events) > 0 do
      send_batch_sync(state.events)
    end

    state = reset_batch_state(state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:batch_timeout, state) do
    if length(state.events) > 0 do
      send_batch_async(state.events)
      state = reset_batch_state(state)
      {:noreply, state}
    else
      state = %{state | timer_ref: nil}
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:batch_result, result}, state) do
    case result do
      {:ok, response} ->
        Logger.debug("Batch sent successfully")
        :telemetry.execute([:mixpanel, :batch, :sent], %{}, %{response: response})

      {:error, %{type: :rate_limit}} ->
        handle_rate_limit(429)
        :telemetry.execute([:mixpanel, :batch, :rate_limited], %{}, %{})

      {:error, error} ->
        Logger.error("Batch send failed: #{inspect(error)}")
        :telemetry.execute([:mixpanel, :batch, :failed], %{}, %{error: error})
    end

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if length(state.events) > 0 do
      Logger.info("Flushing #{length(state.events)} events before shutdown")
      send_batch_sync(state.events)
    end

    :ok
  end

  # Private functions

  defp ensure_event_struct(%Event{} = event), do: event

  defp ensure_event_struct(event_data) when is_map(event_data) do
    Event.new(event_data)
  end

  defp should_send_batch?(events) do
    length(events) >= Config.batch_size()
  end

  defp rate_limited?(state) do
    state.rate_limited and System.monotonic_time(:millisecond) < state.rate_limit_until
  end

  defp ensure_timer_running(%{timer_ref: nil} = state) do
    timer_ref = Process.send_after(self(), :batch_timeout, Config.batch_timeout())
    %{state | timer_ref: timer_ref}
  end

  defp ensure_timer_running(state), do: state

  defp reset_batch_state(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    %{
      state
      | events: [],
        timer_ref: nil,
        rate_limited: false
    }
  end

  defp send_batch_async(events) do
    spawn(fn ->
      result = API.Events.track_batch(events)
      send(__MODULE__, {:batch_result, result})
    end)
  end

  defp send_batch_sync(events) do
    case API.Events.track_batch(events) do
      {:ok, _response} ->
        Logger.debug("Batch sent successfully")

      {:error, error} ->
        Logger.error("Batch send failed: #{inspect(error)}")
    end
  end

  defp calculate_rate_limit_backoff do
    # Simple exponential backoff for MVP
    # 2 seconds
    base_delay = 2000
    # Add up to 1 second of jitter
    jitter = :rand.uniform(1000)
    base_delay + jitter
  end
end
