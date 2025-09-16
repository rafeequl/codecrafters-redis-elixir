# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# Configure the Logger
config :logger,
  # Set the default log level
  level: :debug,

  # Configure console backend
  backends: [:console],

  # Console backend configuration
  console: [
    # Format: timestamp level [module] message
    format: "$time $metadata[$level] $message\n",

    # Metadata to include in logs
    metadata: [:request_id, :user_id, :command, :client_ip, :duration_ms],

    # Colors for different log levels
    colors: [
      debug: :cyan,
      info: :green,
      warn: :yellow,
      error: :red
    ]
  ]

# Configure the application
config :codecrafters_redis,
  # Server configuration
  port: 6379,

  # Logging configuration
  logging: [
    # Enable structured logging
    structured: true,

    # Include performance metrics
    metrics: true,

    # Log level for different components
    levels: [
      tcp_server: :info,
      command_processor: :debug,
      resp_parser: :debug
    ]
  ]
