defmodule CodecraftersRedis.Logging do
  @moduledoc """
  Professional logging module for the Redis server.

  This module provides structured logging with proper context,
  metadata, and log levels following industry best practices.
  """

  require Logger

  @doc """
  Log server lifecycle events with structured metadata.
  """
  def log_server_lifecycle(event, metadata \\ %{}) do
    Logger.info("Server lifecycle event",
      event: event,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end

  @doc """
  Log client connection events with connection details.
  """
  def log_client_connection(event, client_info, metadata \\ %{}) do
    Logger.info("Client connection event",
      event: event,
      client_ip: client_info.ip,
      client_port: client_info.port,
      connection_id: client_info.id,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end

  @doc """
  Log command processing with detailed context.
  """
  def log_command_processing(command, args, metadata \\ %{}) do
    Logger.debug("Command processing",
      command: command,
      args: args,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end

  @doc """
  Log warnings with context.
  """
  def log_warning(message, context, metadata \\ %{}) do
    Logger.warning("Warning occurred",
      message: message,
      context: context,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end

  @doc """
  Log errors with full context.
  """
  def log_error(error, context, metadata \\ %{}) do
    Logger.error("Error occurred",
      error: error,
      context: context,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end

  @doc """
  Log business events with structured data.
  """
  def log_business_event(event_type, event_data, metadata \\ %{}) do
    Logger.info("Business event",
      event_type: event_type,
      event_data: event_data,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    )
  end
end
