defmodule Server do
  @moduledoc """
  Your implementation of a Redis server
  """

  use Application

  def start(_type, _args) do
    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
    # Start Agent to store data
    {:ok, _pid} = Agent.start_link(fn -> %{} end, name: :key_value_store)
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

        # Process each command
        Enum.each(commands, fn command ->
          response = CommandProcessor.process(command)
          :gen_tcp.send(client, response)
        end)

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

defmodule RespParser do
  @moduledoc """
  Simple RESP parser for basic commands
  """

  def parse(data) do
    IO.puts("Raw data: #{inspect(data)}")

    # Split by \r\n and filter out empty strings and length indicators
    parts = data
            |> String.split("\r\n")
            |> Enum.filter(fn part ->
              part != "" and not String.starts_with?(part, "*") and not String.starts_with?(part, "$")
            end)

    IO.puts("Parsed parts: #{inspect(parts)}")

    case parts do
      ["PING"] -> [%{command: "PING", args: []}]
      ["ECHO", message] -> [%{command: "ECHO", args: [message]}]
      ["SET", key, value] -> [%{command: "SET", args: [key, value]}]
      ["SET", key, value, px, ttl] -> [%{command: "SET", args: [key, value, px, ttl]}]
      ["GET", key] -> [%{command: "GET", args: [key]}]
      _ ->
        IO.puts("Unknown command: #{inspect(parts)}")
        []
    end
  end
end

defmodule CommandProcessor do
  @moduledoc """
  Command processor for Redis commands
  """

  @doc """
  Process a command and return the RESP response
  """
  def process(%{command: "PING", args: []}) do
    "+PONG\r\n"
  end

  def process(%{command: "ECHO", args: [message]}) do
    "$#{byte_size(message)}\r\n#{message}\r\n"
  end

  def process(%{command: "SET", args: [key, value]}) do
    Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: value, ttl: nil}) end)
    "+OK\r\n"
  end

  def process(%{command: "SET", args: [key, value, _, ttl]}) do
    ttl_int = String.to_integer(ttl)
    Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: value, ttl: ttl_int, created_at: DateTime.utc_now()}) end)
    "+OK\r\n"
  end

  def process(%{command: "GET", args: [key]}) do
    value = Agent.get(:key_value_store, fn data -> data[key] end)

    # if ttl is not nil, check if the key has expired
    if value != nil and value[:ttl] != nil do
      # Special case: px 0 means expire immediately
      if value[:ttl] == 0 do
        Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
        "-ERR key not found\r\n"
      else
        if DateTime.diff(DateTime.utc_now(), value[:created_at], :millisecond) > value[:ttl] do
          Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
          "-ERR key not found\r\n"
        else
          IO.puts("With TTLValue: #{inspect(value)}")
          "$#{byte_size(value[:value])}\r\n#{value[:value]}\r\n"
        end
      end
    else
      if value == nil do
        "-ERR key not found\r\n"
      else
        IO.puts("Without TTLValue: #{inspect(value)}")
        "$#{byte_size(value[:value])}\r\n#{value[:value]}\r\n"
      end
    end
  end

  def process(%{command: command, args: _args}) do
    IO.puts("Unknown command: #{command}")
    "-ERR unknown command '#{command}'\r\n"
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
