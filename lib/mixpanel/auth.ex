defmodule Mixpanel.Auth do
  @moduledoc """
  Authentication handling for Mixpanel API endpoints.
  """

  @type headers :: [{String.t(), String.t()}]
  @type service_account :: %{
          username: String.t(),
          password: String.t(),
          project_id: String.t()
        }

  @spec track_headers(String.t()) :: headers()
  def track_headers(_project_token) do
    [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]
  end

  @spec import_headers(service_account()) :: headers()
  def import_headers(%{username: username, password: password}) do
    credentials = Base.encode64("#{username}:#{password}")

    [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"authorization", "Basic #{credentials}"}
    ]
  end

  @spec add_token_to_payload(map(), String.t()) :: map()
  def add_token_to_payload(payload, token) do
    put_in(payload, [:properties, :token], token)
  end

  @spec add_project_id_to_payload(map(), String.t()) :: map()
  def add_project_id_to_payload(payload, project_id) do
    put_in(payload, [:properties, :project_id], project_id)
  end
end
