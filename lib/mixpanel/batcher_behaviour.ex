defmodule Mixpanel.BatcherBehaviour do
  @moduledoc """
  Behaviour for Batcher implementations.
  """

  @callback add_event(map()) :: :ok
  @callback flush() :: :ok
end
