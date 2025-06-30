# Basic Mixpanel Usage Examples
#
# This demonstrates how to use the Mixpanel Elixir client for common operations.
# 
# Configuration (in config/config.exs):
# config :mixpanel,
#   project_token: "your_project_token",
#   service_account: %{
#     username: "your_username", 
#     password: "your_password",
#     project_id: "your_project_id"
#   }

# Start the application
{:ok, _} = Application.ensure_all_started(:mixpanel)

# Example 1: Track a single event immediately
{:ok, result} = Mixpanel.track("button_clicked", %{
  device_id: "user123",
  button_id: "submit",
  page: "checkout",
  timestamp: DateTime.utc_now()
}, immediate: true)

IO.puts("Event tracked: #{inspect(result)}")

# Example 2: Track events using batching for high throughput (default behavior)
Mixpanel.track("page_view", %{
  device_id: "user123",
  page: "home"
})

Mixpanel.track("page_view", %{
  device_id: "user456", 
  page: "about"
})

# Flush batched events
Mixpanel.flush()
IO.puts("Batched events flushed")

# Example 3: Import historical events (requires service account)
historical_events = [
  %{
    event: "signup",
    device_id: "user123",
    time: ~U[2023-01-01 00:00:00Z],
    source: "organic",
    email: "user@example.com"
  },
  %{
    event: "first_purchase",
    device_id: "user123", 
    time: ~U[2023-01-02 12:30:00Z],
    amount: 99.99,
    currency: "USD",
    product: "premium_plan"
  }
]

case Mixpanel.track_many(historical_events) do
  {:ok, result} ->
    IO.puts("Import successful: #{inspect(result)}")
  {:error, reason} ->
    IO.puts("Import failed: #{reason}")
end

# Example 4: Error handling
case Mixpanel.track("", %{device_id: "user123"}, immediate: true) do
  {:ok, result} ->
    IO.puts("Success: #{inspect(result)}")
  {:error, reason} ->
    IO.puts("Validation error: #{reason}")
end

IO.puts("Examples completed!")