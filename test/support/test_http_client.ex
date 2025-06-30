defmodule Mixpanel.TestHTTPClient do
  @moduledoc """
  Test HTTP client that uses Req.Test for stubbing HTTP responses.
  """

  @behaviour Mixpanel.HTTPClientBehaviour

  def post(url, opts) do
    # Create a Req client with test plug and disable retries for fast tests
    req = Req.new(plug: {Req.Test, Mixpanel.TestHTTPClient})

    # Remove retry options since we don't want to test Req's retry logic
    opts_without_retry =
      opts
      |> Keyword.delete(:retry)
      |> Keyword.delete(:max_retries)
      |> Keyword.delete(:retry_log_level)

    # Make the request using Req
    Req.post(req, [url: url] ++ opts_without_retry)
  end
end
