# Mixpanel Elixir

[![CI](https://img.shields.io/badge/CI-passing-brightgreen)](https://github.com/example/mixpanel-elixir)
[![Hex.pm](https://img.shields.io/hexpm/v/mixpanel)](https://hex.pm/packages/mixpanel)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue)](https://hexdocs.pm/mixpanel)
[![Elixir](https://img.shields.io/badge/elixir-~%3E%201.18-blueviolet)](https://elixir-lang.org/)

A robust, production-ready Elixir client for the [Mixpanel](https://mixpanel.com/) analytics platform. This library provides a simple, idiomatic Elixir interface for tracking events and importing historical data with automatic batching, rate limiting, and error recovery.

## Features

- 🚀 **High Performance** - Automatic batching for high-throughput event tracking
- 🛡️ **Reliable** - Robust error handling and rate limit management
- 📊 **Complete API Coverage** - Track events and import historical data
- 🔧 **Configurable** - Flexible configuration options for all environments
- ✅ **Well Tested** - Comprehensive test suite
- 📖 **Great Documentation** - Extensive docs with real-world examples

## Installation

Add `mixpanel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mixpanel, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Configuration

Add your Mixpanel credentials to your config:

```elixir
# config/config.exs
config :mixpanel,
  project_token: "your_project_token"

# For historical data import (optional)
config :mixpanel,
  service_account: %{
    username: "your_service_account_username",
    password: "your_service_account_password", 
    project_id: "your_project_id"
  }
```

### 2. Track Events

```elixir
# Anonymous user tracking
{:ok, result} = Mixpanel.track("page_view", %{
  device_id: "device-uuid-123",
  page: "/home",
  referrer: "google.com"
})

# Identified user tracking  
{:ok, result} = Mixpanel.track("purchase", %{
  device_id: "device-uuid-123",
  user_id: "user@example.com",
  amount: 99.99,
  product: "premium_plan"
})
```

### 3. High-Throughput Batching

```elixir
# By default, events are sent immediately
{:ok, result} = Mixpanel.track("purchase", %{device_id: "user1"})

# For high-volume scenarios, use batching (more efficient)
Mixpanel.track("click", %{device_id: "user1"}, batch: true)
Mixpanel.track("click", %{device_id: "user2"}, batch: true)
Mixpanel.track("click", %{device_id: "user3"}, batch: true)

# Events are automatically sent when batch is full or timeout is reached
# Or manually flush when needed
Mixpanel.flush()
```

**Note**: The current default is immediate sending. For most production applications, you might want batching as the default behavior.

## Usage Examples

### Basic Event Tracking

```elixir
# Simple event tracking
Mixpanel.track("button_clicked", %{
  device_id: "device-123",
  button_id: "subscribe",
  page: "pricing"
})

# Track with user identification
Mixpanel.track("feature_used", %{
  device_id: "device-123", 
  user_id: "user@example.com",
  feature: "export_data",
  plan: "premium"
})
```

### Historical Data Import

Perfect for migrating existing analytics data:

```elixir
events = [
  %{
    event: "signup",
    device_id: "device-123",
    time: ~U[2023-01-01 00:00:00Z],
    source: "organic",
    utm_campaign: "summer_sale"
  },
  %{
    event: "first_purchase", 
    device_id: "device-123",
    user_id: "user@example.com",
    time: ~U[2023-01-02 12:30:00Z],
    amount: 49.99,
    product: "starter_plan"
  }
]

{:ok, result} = Mixpanel.import_events(events)
# => {:ok, %{"accepted" => 2}}
```

### Error Handling

```elixir
case Mixpanel.track("purchase", %{device_id: "user123", amount: 99.99}) do
  {:ok, result} ->
    Logger.info("Event tracked successfully: #{inspect(result)}")
  {:error, reason} ->
    Logger.error("Failed to track event: #{reason}")
end
```

## Configuration Options

### Basic Configuration

```elixir
config :mixpanel,
  project_token: "your_project_token",          # Required
  batch_size: 1000,                             # Events per batch (default: 1000)
  batch_timeout: 5000,                          # Batch timeout in ms (default: 5000) 
  max_retries: 3,                               # Retry attempts (default: 3)
  base_url: "https://api.mixpanel.com"          # API base URL (default: official)
```

### Service Account (for imports)

```elixir
config :mixpanel,
  service_account: %{
    username: "service_account_username",
    password: "service_account_password",
    project_id: "your_project_id"
  }
```

### Environment-Specific Config

```elixir
# config/dev.exs
config :mixpanel,
  project_token: "dev_token",
  batch_size: 10  # Smaller batches for development

# config/prod.exs  
config :mixpanel,
  project_token: System.get_env("MIXPANEL_TOKEN"),
  batch_size: 5000,  # Larger batches for production
  batch_timeout: 10000
```

## API Reference

### `Mixpanel.track/3`

Track a single event immediately or add to batch.

**Parameters:**
- `event_name` (String) - Name of the event
- `properties` (Map) - Event properties (must include `:device_id`)  
- `opts` (Keyword) - Options (`:batch` for batching)

**Returns:**
- `{:ok, result}` - Success (immediate tracking)
- `:ok` - Added to batch  
- `{:error, reason}` - Validation or API error

### `Mixpanel.import_events/1`

Import historical events in batch. Requires service account configuration.

**Note**: This function uses Elixir's reserved `import` keyword internally, which may be renamed in future versions to `bulk_track` or similar.

**Parameters:**
- `events` (List) - List of event maps with `:event`, `:device_id`, `:time`

**Returns:**
- `{:ok, %{"accepted" => count}}` - Success
- `{:error, reason}` - Error

### `Mixpanel.flush/0`

Force send all batched events immediately.

**Returns:** `:ok`

## Advanced Usage

### Custom HTTP Client

For testing or custom networking needs:

```elixir
# In test environment
config :mixpanel,
  http_client: MyApp.MockHTTPClient

# Your custom client must implement Mixpanel.HTTPClientBehaviour
defmodule MyApp.MockHTTPClient do
  @behaviour Mixpanel.HTTPClientBehaviour
  
  def post(url, opts) do
    # Your implementation
    {:ok, %{status: 200, body: %{"status" => 1}}}
  end
end
```

### Logging and Debugging

The library includes built-in logging for debugging:

```elixir
# Enable debug logging to see batch operations
config :logger, level: :debug

# You'll see logs like:
# [debug] Batch sent successfully
# [warning] Rate limited, backing off for 2000ms
# [error] Batch send failed: %Mixpanel.Error{...}
```

## Testing

Run the full test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

Code quality checks:

```bash
mix check  # Runs formatting, credo, compilation, and dialyzer
```

## Integration Examples

### Phoenix LiveView

```elixir
defmodule MyAppWeb.PageLive do
  use MyAppWeb, :live_view

  def handle_event("button_click", %{"id" => button_id}, socket) do
    Mixpanel.track("button_clicked", %{
      device_id: socket.assigns.device_id,
      user_id: socket.assigns.current_user.id,
      button_id: button_id,
      page: "home"
    }, batch: true)
    
    {:noreply, socket}
  end
end
```

### Async Background Processing

The library automatically handles background processing with a built-in batcher:

```elixir
# Events are processed asynchronously when using batch: true
Mixpanel.track("user_action", %{device_id: "123"}, batch: true)
Mixpanel.track("another_action", %{device_id: "456"}, batch: true)

# The built-in GenServer automatically sends batches when:
# - Batch size limit is reached (default: 1000 events)
# - Timeout is reached (default: 5 seconds)
# - You manually call flush()
```

## Troubleshooting

### Common Issues

**"project_token not configured"**
- Ensure `project_token` is set in your config
- Check environment variable is loaded: `System.get_env("MIXPANEL_TOKEN")`

**Events not appearing in Mixpanel**
- Verify `device_id` is included in properties
- Check event name is not empty
- Ensure network connectivity to `api.mixpanel.com`

**Import errors**
- Verify service account credentials are correct
- Check that `:time` field uses `DateTime` or `~U[]` sigil
- Ensure all events have required `:event` and `:device_id` fields

### Debug Mode

```elixir
# Enable debug logging
config :logger, level: :debug

# Or set log level for just this library
Logger.put_module_level(Mixpanel, :debug)
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the test suite (`mix test`)
5. Run code quality checks (`mix check`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📚 [Documentation](https://hexdocs.pm/mixpanel)
- 🐛 [Issue Tracker](https://github.com/example/mixpanel-elixir/issues)
- 💬 [Discussions](https://github.com/example/mixpanel-elixir/discussions)

## Related Projects

- [Official Mixpanel JavaScript Library](https://github.com/mixpanel/mixpanel-js)
- [Official Mixpanel Python Library](https://github.com/mixpanel/mixpanel-python)
- [Mixpanel HTTP API Documentation](https://developer.mixpanel.com/reference/overview)

---

Built with ❤️ for the Elixir community