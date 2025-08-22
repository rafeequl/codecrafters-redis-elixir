defmodule Server do
  @moduledoc """
  Your implementation of a Redis server
  """

  use Application

  def start(_type, _args) do
    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
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

    process_client_commands(client)

    # After processing the request, accept the next connection
    accept_connections(socket)
  end

  defp process_client_commands(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        IO.puts("Raw data: #{inspect(data)}")
        
        # Parse RESP format to extract commands
        commands = parse_resp(data)
        IO.puts("Parsed commands: #{inspect(commands)}")
        
        # Process each command
        Enum.each(commands, fn command ->
          if command == "PING" do
            :gen_tcp.send(client, "+PONG\r\n")
          end
        end)
        
        # Continue processing more commands from this client
        process_client_commands(client)
        
      {:error, :closed} ->
        IO.puts("Client connection closed")
        :gen_tcp.close(client)
      {:error, reason} ->
        IO.puts("Error receiving data from client: #{reason}")
        :gen_tcp.close(client)
    end
  end

  defp parse_resp(data) do
    # Simple RESP parser for basic commands
    # For "*1\r\n$4\r\nPING\r\n" format
    case String.split(data, "\r\n", trim: true) do
      ["*1", "$4", "PING"] -> ["PING"]
      ["*1", "$4", "PING", ""] -> ["PING"]
      _ -> 
        IO.puts("Unknown RESP format: #{inspect(data)}")
        []
    end
  end
end

defmodule CLI do
  def main(_args) do
    # Start the Server application
    {:ok, _pid} = Application.ensure_all_started(:codecrafters_redis)

    # Run forever
    Process.sleep(:infinity)
  end
end
