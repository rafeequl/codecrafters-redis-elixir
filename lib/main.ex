defmodule Server do
  @moduledoc """
  Main application module for the Redis server.

  This module implements the Application behavior and is responsible
  for starting the TCP server and key-value store when the application starts.
  """

  use Application

  alias TcpServer

  @doc """
  Starts the Redis server application.

  This function is called automatically when the application starts.
  It initializes the TCP server and key-value store.
  """
  def start(_type, _args) do
    IO.puts("Initializing Redis server components...")

    # Start the TCP server (which will also start the Agent)
    {:ok, _pid} = TcpServer.start(nil, nil)
    IO.puts("Redis server components initialized successfully")
    {:ok, self()}
  end

  @doc """
    {:ok, _pid} = TcpServer.start(nil, nil)
  Stops the Redis server application.

  This function is called automatically when the application stops.
  """
  def stop(_state) do
    IO.puts("Shutting down Redis server...")
    :ok
  end
end
