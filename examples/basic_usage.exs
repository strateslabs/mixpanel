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
  distinct_id: "user123",
  properties: %{
    button_id: "submit",
    page: "checkout",
    timestamp: DateTime.utc_now()
  }
})

IO.puts("Event tracked: #{inspect(result)}")

# Example 2: Track events using batching for high throughput
Mixpanel.track("page_view", %{
  distinct_id: "user123",
  properties: %{page: "home"}
}, batch: true)

Mixpanel.track("page_view", %{
  distinct_id: "user456", 
  properties: %{page: "about"}
}, batch: true)

# Flush batched events
Mixpanel.flush()
IO.puts("Batched events flushed")

# Example 3: Import historical events (requires service account)
historical_events = [
  %{
    event: "signup",
    distinct_id: "user123",
    time: ~U[2023-01-01 00:00:00Z],
    properties: %{
      source: "organic",
      email: "user@example.com"
    }
  },
  %{
    event: "first_purchase",
    distinct_id: "user123", 
    time: ~U[2023-01-02 12:30:00Z],
    properties: %{
      amount: 99.99,
      currency: "USD",
      product: "premium_plan"
    }
  }
]

case Mixpanel.import_events(historical_events) do
  {:ok, result} ->
    IO.puts("Import successful: #{inspect(result)}")
  {:error, reason} ->
    IO.puts("Import failed: #{reason}")
end

# Example 4: Error handling
case Mixpanel.track("", %{distinct_id: "user123"}) do
  {:ok, result} ->
    IO.puts("Success: #{inspect(result)}")
  {:error, reason} ->
    IO.puts("Validation error: #{reason}")
end

IO.puts("Examples completed!")