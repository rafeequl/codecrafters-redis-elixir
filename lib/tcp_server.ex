defmodule TcpServer do
  @moduledoc """
  Your implementation of a Redis server
  """

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
  end

  @doc """
  Listen for incoming connections
  """
  def listen() do
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    IO.puts("Logs from your program will appear here!")

    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    {:ok, socket} = :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true])

    accept_connections(socket)
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
        IO.puts("Raw data: #{inspect(data)}")

        # Parse RESP format to extract commands
        commands = RespParser.parse(data)
        IO.puts("Parsed commands: #{inspect(commands)}")

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
        IO.puts("Client connection closed")
        :gen_tcp.close(client)

      {:error, reason} ->
        IO.puts("Error receiving data from client: #{reason}")
        :gen_tcp.close(client)
    end
  end
end
