defmodule Server do
  @moduledoc """
  Main application module for the Redis server.

  This module implements the Application behavior and is responsible
  for starting the TCP server and key-value store when the application starts.
  """

  use Application
  alias CodecraftersRedis.Logging
  alias TcpServer
  alias CommandProcessor.ListCommandsServer
  alias CommandProcessor.StreamCommandServer

  @doc """
  Starts the Redis server application.

  This function is called automatically when the application starts.
  It initializes the TCP server and key-value store.
  """
  def start(_type, _args) do
    Logging.log_server_lifecycle("application_starting", %{
      application: :codecrafters_redis,
      environment: get_environment()
    })

    # Start the List Commands GenServer
    case ListCommandsServer.start_link([]) do
      {:ok, _list_server_pid} ->
        :ok
      {:error, {:already_started, _pid}} ->
        :ok
    end

    # Start the Stream Commands GenServer
    case StreamCommandServer.start_link([]) do
      {:ok, _stream_server_pid} ->
        :ok
      {:error, {:already_started, _pid}} ->
        :ok
    end

    # Start the TCP server (which will also start the Agent)
    {:ok, _pid} = TcpServer.start(nil, nil)

    Logging.log_server_lifecycle("application_started", %{
      application: :codecrafters_redis,
      status: "success",
      components: ["list_commands_server", "tcp_server", "key_value_store"]
    })

    {:ok, self()}
  end

  @doc """
  Stops the Redis server application.

  This function is called automatically when the application stops.
  """
  def stop(_state) do
    Logging.log_server_lifecycle("application_stopping", %{
      application: :codecrafters_redis,
      reason: "normal_shutdown"
    })

    :ok
  end

  defp get_environment do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      :prod
    end
  end
end
