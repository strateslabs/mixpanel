defmodule Mixpanel.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    token = Application.get_env(:mixpanel, :token)
    active = Application.get_env(:mixpanel, :active)

    if token == nil do
      raise "Please set :mixpanel, :token in your app environment's config"
    end

    children = [
      {Mixpanel.Client, [token: token, active: active]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mixpanel.Supervisor]
    Supervisor.init(children, opts)
  end
end
