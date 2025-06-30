defmodule Mixpanel.Client do
  @moduledoc """
  HTTP client for Mixpanel API endpoints.
  """

  alias Mixpanel.{Auth, Config, Error}
  require Logger

  @type response :: {:ok, map()} | {:error, Error.t()}

  @spec track([map()], String.t()) :: response()
  def track(events, project_token) do
    url = "#{Config.base_url()}/track"
    headers = Auth.track_headers(project_token)

    # Add token to each event and prepare payload
    events_with_token = Enum.map(events, &Auth.add_token_to_payload(&1, project_token))

    payload =
      case events_with_token do
        [single_event] -> single_event
        multiple_events -> multiple_events
      end

    make_request(url, payload, headers)
  end

  @spec import([map()], Auth.service_account()) :: response()
  def import(events, service_account) do
    url = "#{Config.base_url()}/import"
    headers = Auth.import_headers(service_account)

    # Add token and project_id to each event
    project_token = Config.project_token()

    events_with_auth =
      events
      |> Enum.map(&Auth.add_token_to_payload(&1, project_token))
      |> Enum.map(&Auth.add_project_id_to_payload(&1, service_account.project_id))

    make_request(url, events_with_auth, headers)
  end

  @spec retry_with_backoff(function(), pos_integer(), pos_integer()) :: response()
  def retry_with_backoff(request_fn, max_retries, current_attempt \\ 1) do
    case request_fn.() do
      {:ok, result} ->
        {:ok, result}

      {:error, %Error{retryable?: true}} when current_attempt < max_retries ->
        backoff = calculate_backoff(current_attempt)
        Process.sleep(backoff)
        retry_with_backoff(request_fn, max_retries, current_attempt + 1)

      error ->
        error
    end
  end

  @spec calculate_backoff(pos_integer()) :: pos_integer()
  def calculate_backoff(attempt) do
    # Exponential backoff in ms
    base_delay = :math.pow(2, attempt) * 1000
    # Add up to 1 second of jitter
    jitter = :rand.uniform(1000)
    trunc(base_delay + jitter)
  end

  defp make_request(url, payload, headers) do
    http_client = Application.get_env(:mixpanel, :http_client, Req)

    case http_client.post(url, json: payload, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        parse_success_response(body)

      {:ok, %{status: 429, body: _body}} ->
        {:error, Error.new(:rate_limit, "Rate limited")}

      {:ok, %{status: 400, body: body}} ->
        message = extract_error_message(body)
        {:error, Error.new(:validation, message)}

      {:ok, %{status: status, body: _body}} when status in [401, 403] ->
        {:error, Error.new(:auth, "Authentication failed")}

      {:ok, %{status: status, body: _body}} when status >= 500 ->
        {:error, Error.new(:server, "Server error")}

      {:error, error} ->
        {:error, Error.new(:network, "Network error: #{inspect(error)}")}
    end
  end

  defp parse_success_response(%{"status" => 1}) do
    {:ok, %{accepted: 1}}
  end

  defp parse_success_response(%{"num_records_imported" => count}) do
    {:ok, %{accepted: count}}
  end

  defp parse_success_response(body) when is_map(body) do
    # For batch requests, assume all events in the payload were accepted
    # This is a simplification for the MVP
    {:ok, %{accepted: 1}}
  end

  defp parse_success_response(_body) do
    {:ok, %{accepted: 1}}
  end

  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error

  defp extract_error_message(%{"error" => error}) when is_map(error) do
    Map.get(error, "message", "Validation error")
  end

  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(_), do: "Unknown error"
end
