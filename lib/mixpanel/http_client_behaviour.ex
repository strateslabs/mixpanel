defmodule Mixpanel.HTTPClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.
  """

  @callback post(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
end
