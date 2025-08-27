defmodule CLI do
  @moduledoc """
  Command Line Interface entry point for the Redis server.

  This module serves as the main entry point when running the application
  as an executable or with `mix run`.
  """

  alias CodecraftersRedis.Logging

  @doc """
  Main entry point for the CLI application.

  Starts the Redis server application and keeps it running.
  """
  def main(_args) do
    Logging.log_server_lifecycle("cli_startup", %{
      version: "1.0.0",
      environment: get_environment()
    })

    # Start the Server application
    case Application.ensure_all_started(:codecrafters_redis) do
      {:ok, _started} ->
        Logging.log_server_lifecycle("server_started", %{
          port: 6379,
          status: "success"
        })

        Logging.log_business_event("server_ready", %{
          message: "Press Ctrl+C to stop the server",
          port: 6379
        })

        # Run forever
        Process.sleep(:infinity)

      {:error, reason} ->
        Logging.log_error(reason, "server_startup_failed", %{
          port: 6379,
          error_type: "application_startup_error"
        })
        System.halt(1)
    end
  end

  defp get_environment do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      :prod
    end
  end
end
