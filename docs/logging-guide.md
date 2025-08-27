# Professional Logging Guide

This guide shows how to implement industry-standard logging practices in your Elixir applications, specifically demonstrated in the Codecrafters Redis project.

## Overview

We've implemented a structured logging system that follows the best practices used by major open-source Elixir projects like:
- Phoenix Framework
- Ecto
- Absinthe
- Broadway

## Key Principles

### 1. **Structured Logging**
Instead of simple text messages, we log structured data with metadata:

```elixir
# ❌ Bad: Simple text logging
Logger.info("User logged in")

# ✅ Good: Structured logging with context
Logging.log_business_event("user_login", %{
  user_id: user.id,
  ip_address: conn.remote_ip,
  user_agent: get_req_header(conn, "user-agent")
})
```

### 2. **Appropriate Log Levels**
- **`debug`**: Detailed information for debugging (raw data, internal state)
- **`info`**: General application flow (startup, shutdown, connections)
- **`warn`**: Something unexpected but recoverable (unknown commands)
- **`error`**: Something went wrong (server failures, connection errors)

### 3. **Context and Metadata**
Always include relevant context with your logs:

```elixir
Logging.log_command_processing("command_executed", [command, args], %{
  command: command,
  args_count: length(args),
  user_id: current_user_id,
  request_id: request_id
})
```

## Usage Examples

### Server Lifecycle Events

```elixir
# Application startup
Logging.log_server_lifecycle("application_starting", %{
  application: :codecrafters_redis,
  environment: Mix.env(),
  version: "1.0.0"
})

# Application shutdown
Logging.log_server_lifecycle("application_stopping", %{
  application: :codecrafters_redis,
  reason: "normal_shutdown"
})
```

### Client Connection Events

```elixir
# New connection
Logging.log_client_connection("connection_established", %{
  ip: client_ip,
  port: client_port,
  id: connection_id
})

# Connection closed
Logging.log_client_connection("connection_closed", %{
  ip: client_ip,
  port: client_port,
  id: connection_id,
  duration_ms: connection_duration
})
```

### Command Processing

```elixir
# Command received
Logging.log_command_processing("command_received", [command, args], %{
  command: command,
  args_count: length(args),
  client_id: client_id
})

# Command executed
Logging.log_command_result(command, result, duration_ms, %{
  success: true,
  response_size: byte_size(result)
})
```

### Error Handling

```elixir
# Simple error
Logging.log_error(error, "database_connection_failed", %{
  database: "redis",
  retry_count: retry_count
})

# Error with stacktrace (inside rescue blocks)
try do
  risky_operation()
rescue
  error ->
    Logging.log_error_with_stacktrace(error, "operation_failed", __STACKTRACE__, %{
      operation: "risky_operation",
      context: "data_processing"
    })
end
```

### Performance Metrics

```elixir
# Response time
Logging.log_metric("response_time", duration_ms, "milliseconds", %{
  endpoint: "/api/commands",
  method: "POST"
})

# Throughput
Logging.log_metric("commands_per_second", commands_count, "commands", %{
  time_window: "1_second"
})
```

## Configuration

### Logger Configuration

```elixir
# config/config.exs
config :logger,
  level: :info,
  backends: [:console],
  console: [
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :user_id, :command, :client_ip, :duration_ms],
    colors: [
      debug: :cyan,
      info: :green,
      warn: :yellow,
      error: :red
    ]
  ]
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :logger, level: :debug

# config/prod.exs
config :logger, level: :warn
```

## Best Practices

### 1. **Never Log Sensitive Information**
```elixir
# ❌ Bad: Logging passwords
Logging.log_command_processing("auth", [username, password], %{})

# ✅ Good: Sanitized logging
Logging.log_command_processing("auth", [username, "***"], %{
  auth_method: "password"
})
```

### 2. **Use Consistent Naming**
```elixir
# Use snake_case for event names and metadata keys
Logging.log_business_event("user_account_created", %{
  user_id: user.id,
  account_type: "premium"
})
```

### 3. **Include Request IDs for Tracing**
```elixir
# Generate a unique request ID for each request
request_id = Ecto.UUID.generate()

Logging.log_command_processing("command_started", [command], %{
  request_id: request_id,
  command: command
})
```

### 4. **Log at the Right Level**
```elixir
# Debug: Internal implementation details
Logging.log_command_processing("internal_state", [state], %{})

# Info: Business events
Logging.log_business_event("key_set", %{key: key, value_size: byte_size(value)})

# Warn: Recoverable issues
Logging.log_warning("rate_limit_exceeded", "client_throttling", %{
  client_id: client_id,
  retry_after: retry_after
})

# Error: System failures
Logging.log_error(error, "database_connection_failed", %{
  database: "redis",
  retry_count: retry_count
})
```

## Testing

### Configure Test Logging

```elixir
# test/test_helper.exs
Logger.configure(level: :warn)  # Only show warnings and errors during tests
ExUnit.start()
```

### Test Logging Behavior

```elixir
# test/logging_test.exs
defmodule LoggingTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  
  test "logs are properly structured" do
    log = capture_log(fn ->
      Logging.log_business_event("test_event", %{test: true})
    end)
    
    assert log =~ "Business event"
    assert log =~ "test_event"
  end
end
```

## Integration with External Tools

### JSON Formatting for Log Aggregators

```elixir
# config/prod.exs
config :logger,
  backends: [:console, {LoggerFileBackend, :json}],
  json: [
    format: "$json\n",
    metadata: :all
  ]
```

### Structured Logging for ELK Stack

```elixir
# Use structured logging that can be easily parsed by Logstash
Logging.log_business_event("user_action", %{
  action: "key_set",
  user_id: user_id,
  key: key,
  timestamp: DateTime.utc_now()
})
```

## Performance Considerations

### 1. **Avoid String Interpolation in Debug Logs**
```elixir
# ❌ Bad: Always evaluates
Logger.debug("Processing #{inspect(large_data_structure)}")

# ✅ Good: Lazy evaluation
Logger.debug("Processing data", data: large_data_structure)
```

### 2. **Use Conditional Logging**
```elixir
# Only log when debug is enabled
if Logger.level() == :debug do
  Logging.log_command_processing("detailed_debug", [data], %{})
end
```

### 3. **Batch Log Operations**
```elixir
# Log multiple related events together
Logging.log_business_event("batch_operations_completed", %{
  operations: [
    %{type: "set", key: "key1", success: true},
    %{type: "set", key: "key2", success: true}
  ],
  total_count: 2
})
```

This logging system provides you with professional-grade observability that scales from development to production, making debugging easier and providing valuable insights into your application's behavior.
