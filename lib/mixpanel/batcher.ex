defmodule Mixpanel.Batcher do
  @moduledoc """
  GenServer for batching events before sending to Mixpanel.
  """

  use GenServer
  alias Mixpanel.{API, Config, Event}
  require Logger

  @type state :: %{
          events: [Event.t()],
          timer_ref: reference() | nil
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

  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end


  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{
      events: [],
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:add_event, event_data}, state) do
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


  @impl GenServer
  def handle_call(:flush, _from, state) do
    if length(state.events) > 0 do
      send_batch_sync(state.events)
    end

    state = reset_batch_state(state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
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
        Logger.warning("Batch rate limited - Req will handle retry automatically")
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
        timer_ref: nil
    }
  end

  defp send_batch_async(events) do
    Task.start(fn ->
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

end
