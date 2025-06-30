defmodule Mixpanel.API.EventsBehaviour do
  @moduledoc """
  Behaviour for Events API implementations.
  """

  @callback track(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()} | :ok
  @callback track_batch([map()]) :: {:ok, map()} | {:error, any()}
  @callback import([map()]) :: {:ok, map()} | {:error, any()}
end
