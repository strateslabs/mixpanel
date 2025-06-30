defmodule Mixpanel.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Mixpanel.Supervisor.start_link()
  end
end
