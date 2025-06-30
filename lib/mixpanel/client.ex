defmodule Mixpanel.Client do
  @moduledoc """
  Mixpanel client.
  """
  use GenServer

  require Logger

  @track_endpoint "https://api.mixpanel.com/track"
  @engage_endpoint "https://api.mixpanel.com/engage"

  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, {:ok, config}, Keyword.put(opts, :name, __MODULE__))
  end

  @doc """
  Tracks a event.

  See `Mixpanel.track/3`
  """
  @spec track(String.t(), Map.t()) :: :ok
  def track(event, properties \\ %{}) do
    GenServer.cast(__MODULE__, {:track, event, properties})
  end

  @doc """
  Updates a user profile.

  See `Mixpanel.engage/4`.
  """
  @spec engage(Map.t()) :: :ok
  def engage(event) do
    GenServer.cast(__MODULE__, {:engage, event})
  end

  @impl GenServer
  def init({:ok, config}) do
    {:ok, Map.new(config)}
  end

  @impl GenServer
  def handle_cast({:track, event, properties}, %{token: token, active: true} = state) do
    Logger.info("Tracking Mixpanel event: #{inspect(event)}, #{inspect(properties)}")

    data =
      %{event: event, properties: Map.put(properties, :token, token)}
      |> Jason.encode!()
      |> :base64.encode()

    case Req.get(@track_endpoint, params: [data: data]) do
      {:ok, %Req.Response{status: 200, body: "1"}} ->
        :ok

      {:ok, response} ->
        Logger.warning(
          "Problem tracking Mixpanel event: #{inspect(event)}, #{inspect(properties)} Got: #{inspect(response)}"
        )

      {:error, error} ->
        Logger.warning(
          "Problem tracking Mixpanel event: #{inspect(event)}, #{inspect(properties)} Error: #{inspect(error)}"
        )
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:engage, event}, %{token: token, active: true} = state) do
    Logger.info("Saving Mixpanel profile: #{inspect(event)}")

    data =
      event
      |> Map.put(:"$token", token)
      |> Jason.encode!()
      |> :base64.encode()

    case Req.get(@engage_endpoint, params: [data: data]) do
      {:ok, %Req.Response{status: 200, body: "1"}} ->
        :ok

      {:ok, response} ->
        Logger.warning(
          "Problem tracking Mixpanel profile update: #{inspect(event)} Got: #{inspect(response)}"
        )

      {:error, error} ->
        Logger.warning(
          "Problem tracking Mixpanel profile update: #{inspect(event)} Error: #{inspect(error)}"
        )
    end

    {:noreply, state}
  end

  # No events submitted when env configuration is set to false.
  def handle_cast(_request, %{active: false} = state) do
    {:noreply, state}
  end
end
