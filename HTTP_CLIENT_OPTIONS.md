# HTTP Client Configuration

The Mixpanel client allows you to configure any Req HTTP client options via the `:http_client_options` configuration key.

## Default Configuration

By default, the following options are set:

```elixir
config :mixpanel,
  http_client_options: [
    retry: :transient,       # Retry on transient errors (429, 5xx, network issues)
    max_retries: 3,         # Maximum number of retry attempts
    retry_log_level: :debug # Log level for retry attempts
  ]
```

## Customizing HTTP Client Options

You can override any of these defaults or add additional Req options:

### Disable Retries

```elixir
config :mixpanel,
  http_client_options: [
    retry: false
  ]
```

### Custom Retry Configuration

```elixir
config :mixpanel,
  http_client_options: [
    retry: :safe_transient,   # Only retry safe transient errors
    max_retries: 1,           # Fewer retries
    retry_log_level: :info    # Different log level
  ]
```

### Configure Timeouts

```elixir
config :mixpanel,
  http_client_options: [
    receive_timeout: 30_000,  # 30 second timeout
    retry: :transient,
    max_retries: 2
  ]
```

### Advanced Configuration

```elixir
config :mixpanel,
  http_client_options: [
    # Connection settings
    receive_timeout: 30_000,
    
    # Retry settings
    retry: :transient,
    max_retries: 5,
    retry_log_level: :warn,
    
    # Response handling
    decode_body: true,
    
    # Additional Req options...
  ]
```

## Available Options

Any valid [Req option](https://hexdocs.pm/req/Req.html#request/1-options) can be used. Common options include:

- `:retry` - Retry strategy (`:transient`, `:safe_transient`, `false`, or custom function)
- `:max_retries` - Maximum number of retry attempts
- `:retry_log_level` - Log level for retry messages
- `:receive_timeout` - Timeout for receiving response
- `:decode_body` - Whether to decode response body
- `:compressed` - Whether to accept compressed responses

## How It Works

The HTTP client options are merged with request-specific options, with user options taking precedence:

1. **Default options** are set (json payload, headers)
2. **User http_client_options** are merged in, overriding defaults
3. The final options are passed to Req

This gives you complete control over the HTTP client behavior while maintaining sensible defaults.