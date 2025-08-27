defmodule TcpServer do
  @moduledoc """
  Your implementation of a Redis server
  """

  alias CodecraftersRedis.Logging
  alias RespParser
  alias CommandProcessor

  @doc """
  Start the TCP server
  """
  def start(_type, _args) do
    # Start the TCP server
    Task.start(fn -> listen() end)

    # Start Agent to store data (or get existing one if already started)
    case Agent.start_link(fn -> %{} end, name: :key_value_store) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end

    # Start Agent for waiting queues (or get existing one if already started)
    case Agent.start_link(fn -> %{} end, name: :waiting_queues) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @doc """
  Listen for incoming connections
  """
  def listen() do
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    Logging.log_server_lifecycle("tcp_server_listening", %{
      port: 6379,
      reuseaddr: true
    })

    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    case :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        accept_connections(socket)

      {:error, :eaddrinuse} ->
        # Port is already in use, server is already running
        Logging.log_warning("Port already in use", "port_conflict", %{
          port: 6379,
          reason: "address_already_in_use"
        })
        :ok

      {:error, reason} ->
        Logging.log_error(reason, "tcp_server_startup_failed", %{
          port: 6379,
          error_type: "socket_listen_error"
        })
        :error
    end
  end


  defp accept_connections(socket) do
    {:ok, client} = :gen_tcp.accept(socket)

    # Process the client commands in a separate task, this allows us to accept more connections
    Task.start(fn -> process_client_commands(client) end)

    # After processing the request, accept the next connection
    accept_connections(socket)
  end

  defp process_client_commands(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        Logging.log_command_processing("raw_data_received", [data], %{
          data_size: byte_size(data),
          client_pid: inspect(client)
        })

        # Parse RESP format to extract commands
        commands = RespParser.parse(data)
        Logging.log_command_processing("commands_parsed", commands, %{
          command_count: length(commands),
          client_pid: inspect(client)
        })

        # Process each command or send error if no commands parsed
        if Enum.empty?(commands) do
          # Send error response for unknown/unparseable commands
          :gen_tcp.send(client, "-ERR unknown command\r\n")
        else
          # Process each command
          Enum.each(commands, fn command ->
            response = CommandProcessor.process(command)
            :gen_tcp.send(client, response)
          end)
        end

        # Continue reading more commands from the same connection
        process_client_commands(client)

      {:error, :closed} ->
        Logging.log_client_connection("connection_closed", %{
          ip: "unknown",
          port: "unknown",
          id: inspect(client)
        })
        :gen_tcp.close(client)

      {:error, reason} ->
        Logging.log_error(reason, "client_data_receive_error", %{
          client_pid: inspect(client),
          error_type: "tcp_recv_error"
        })
        :gen_tcp.close(client)
    end
  end
end
