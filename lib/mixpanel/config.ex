defmodule Mixpanel.Config do
  @moduledoc """
  Configuration management for the Mixpanel client.
  """

  @type service_account :: %{
          username: String.t(),
          password: String.t(),
          project_id: String.t()
        }

  @type config :: %{
          project_token: String.t(),
          service_account: service_account() | nil,
          batch_size: pos_integer(),
          batch_timeout: pos_integer(),
          base_url: String.t(),
          http_client_options: keyword()
        }

  @default_config %{
    batch_size: 1000,
    batch_timeout: 5000,
    base_url: "https://api.mixpanel.com",
    http_client_options: [
      retry: :transient,
      max_retries: 3,
      retry_log_level: :debug
    ]
  }

  @spec get() :: config()
  def get do
    config = Application.get_all_env(:mixpanel)

    @default_config
    |> Map.merge(Enum.into(config, %{}))
    # Ensure service_account key exists
    |> Map.put_new(:service_account, nil)
    |> validate_config!()
  end

  @spec project_token() :: String.t()
  def project_token do
    case Application.get_env(:mixpanel, :project_token) do
      nil -> raise "Mixpanel project_token not configured"
      token -> token
    end
  end

  @spec service_account() :: service_account() | nil
  def service_account do
    Application.get_env(:mixpanel, :service_account)
  end

  @spec batch_size() :: pos_integer()
  def batch_size do
    Application.get_env(:mixpanel, :batch_size, @default_config.batch_size)
  end

  @spec batch_timeout() :: pos_integer()
  def batch_timeout do
    Application.get_env(:mixpanel, :batch_timeout, @default_config.batch_timeout)
  end

  @spec base_url() :: String.t()
  def base_url do
    Application.get_env(:mixpanel, :base_url, @default_config.base_url)
  end

  @spec http_client_options() :: keyword()
  def http_client_options do
    Application.get_env(:mixpanel, :http_client_options, @default_config.http_client_options)
  end

  defp validate_config!(config) do
    cond do
      not Map.has_key?(config, :project_token) or config.project_token == nil ->
        raise "Mixpanel project_token not configured"

      not is_binary(config.project_token) ->
        raise ArgumentError, "project_token must be a string"

      true ->
        :ok
    end

    if Map.has_key?(config, :service_account) and config.service_account do
      validate_service_account!(config.service_account)
    end

    unless is_integer(config.batch_size) and config.batch_size > 0 do
      raise ArgumentError, "batch_size must be a positive integer"
    end

    unless is_integer(config.batch_timeout) and config.batch_timeout > 0 do
      raise ArgumentError, "batch_timeout must be a positive integer"
    end

    unless is_list(config.http_client_options) do
      raise ArgumentError, "http_client_options must be a keyword list"
    end

    config
  end

  defp validate_service_account!(service_account) do
    required_keys = [:username, :password, :project_id]

    Enum.each(required_keys, fn key ->
      unless Map.has_key?(service_account, key) and is_binary(service_account[key]) do
        raise ArgumentError, "service_account.#{key} must be a string"
      end
    end)
  end
end
