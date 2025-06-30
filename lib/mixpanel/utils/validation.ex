defmodule Mixpanel.Utils.Validation do
  @moduledoc """
  Event validation utilities for the Mixpanel client.
  """

  # 1MB
  @max_event_size 1024 * 1024
  @max_properties 255

  @spec validate_event_size(map()) :: :ok | {:error, String.t()}
  def validate_event_size(event) do
    size = :erlang.byte_size(:erlang.term_to_binary(event))

    if size > @max_event_size do
      {:error, "event size exceeds 1MB limit"}
    else
      :ok
    end
  end

  @spec validate_property_count(map()) :: :ok | {:error, String.t()}
  def validate_property_count(properties) when is_map(properties) do
    count = map_size(properties)

    if count > @max_properties do
      {:error, "event has too many properties (max #{@max_properties})"}
    else
      :ok
    end
  end

  @spec validate_nesting_depth(any(), pos_integer()) :: :ok | {:error, String.t()}
  def validate_nesting_depth(data, max_depth) do
    case check_depth(data, 1, max_depth) do
      :ok -> :ok
      {:error, _} -> {:error, "properties nesting too deep (max #{max_depth} levels)"}
    end
  end

  @spec validate_required_fields(map(), [atom()]) :: :ok | {:error, String.t()}
  def validate_required_fields(data, required_fields) do
    Enum.reduce_while(required_fields, :ok, fn field, _acc ->
      case Map.get(data, field) do
        nil ->
          {:halt, {:error, "#{field} is required"}}

        "" ->
          {:halt, {:error, "#{field} cannot be empty"}}

        _value ->
          {:cont, :ok}
      end
    end)
  end

  defp check_depth(data, current_depth, max_depth) when is_map(data) do
    if current_depth > max_depth do
      {:error, :too_deep}
    else
      Enum.reduce_while(data, :ok, fn {_key, value}, _acc ->
        case check_depth(value, current_depth + 1, max_depth) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp check_depth(data, current_depth, max_depth) when is_list(data) do
    if current_depth > max_depth do
      {:error, :too_deep}
    else
      Enum.reduce_while(data, :ok, fn item, _acc ->
        case check_depth(item, current_depth, max_depth) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp check_depth(_data, _current_depth, _max_depth), do: :ok
end
