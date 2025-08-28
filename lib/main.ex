defmodule Server do
  @moduledoc """
  Main application module for the Redis server.

  This module implements the Application behavior and is responsible
  for starting the TCP server and key-value store when the application starts.
  """

  use Application
  alias CodecraftersRedis.Logging
  alias TcpServer

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

    # Start the TCP server (which will also start the Agent)
    {:ok, _pid} = TcpServer.start(nil, nil)

    Logging.log_server_lifecycle("application_started", %{
      application: :codecrafters_redis,
      status: "success",
      components: ["tcp_server", "key_value_store"]
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
