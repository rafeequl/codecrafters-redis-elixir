defmodule CLI do
  @moduledoc """
  Command Line Interface entry point for the Redis server.

  This module serves as the main entry point when running the application
  as an executable or with `mix run`.
  """

  @doc """
  Main entry point for the CLI application.

  Starts the Redis server application and keeps it running.
  """
  def main(_args) do
    IO.puts("Starting Redis server...")

    # Start the Server application
    case Application.ensure_all_started(:codecrafters_redis) do
      {:ok, _started} ->
        IO.puts("Redis server started successfully on port 6379")
        IO.puts("Press Ctrl+C to stop the server")

        # Run forever
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts("Failed to start Redis server: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
