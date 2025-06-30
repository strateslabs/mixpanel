defmodule Mixpanel.Error do
  @moduledoc """
  Error struct for Mixpanel API errors.
  """

  @type error_type :: :rate_limit | :validation | :auth | :server | :network
  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map(),
          retryable?: boolean()
        }

  defstruct [:type, :message, :details, :retryable?]

  @spec new(error_type(), String.t(), map()) :: t()
  def new(type, message, details \\ %{}) do
    %__MODULE__{
      type: type,
      message: message,
      details: details,
      retryable?: retryable?(type)
    }
  end

  defp retryable?(:rate_limit), do: true
  defp retryable?(:server), do: true
  defp retryable?(:network), do: true
  defp retryable?(:validation), do: false
  defp retryable?(:auth), do: false
end
