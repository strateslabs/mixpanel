defmodule Mixpanel.Application do
  @moduledoc """
  OTP Application for the Mixpanel client.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Mixpanel.Batcher, []}
    ]

    opts = [strategy: :one_for_one, name: Mixpanel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def stop(_state) do
    # Ensure batcher flushes before shutdown
    Mixpanel.Batcher.flush()
    :ok
  end
end
