defmodule CommandProcessor do
  @moduledoc """
  Command processor for Redis commands
  """

  @doc """
  Process a command and return the RESP response
  """
  def process(%{command: "COMMAND", args: []}) do
    # Return information about available commands
    # This is typically sent by Redis CLI when it first connects
    "*0\r\n"
  end

  def process(%{command: "COMMAND", args: ["DOCS"]}) do
    # Handle COMMAND DOCS - return empty array
    "*0\r\n"
  end

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

    Agent.update(:key_value_store, fn data ->
      Map.put(data, key, %{value: value, ttl: ttl_int, created_at: DateTime.utc_now()})
    end)

    "+OK\r\n"
  end

  def process(%{command: "GET", args: [key]}) do
    value = Agent.get(:key_value_store, fn data -> data[key] end)

    # if ttl is not nil, check if the key has expired
    if value != nil and value[:ttl] != nil do
      # Special case: px 0 means expire immediately
      if value[:ttl] == 0 do
        Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
        "$-1\r\n"
      else
        if DateTime.diff(DateTime.utc_now(), value[:created_at], :millisecond) > value[:ttl] do
          Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
          "$-1\r\n"
        else
          IO.puts("With TTLValue: #{inspect(value)}")
          "$#{byte_size(value[:value])}\r\n#{value[:value]}\r\n"
        end
      end
    else
      if value == nil do
        "$-1\r\n"
      else
        IO.puts("Without TTLValue: #{inspect(value)}")
        "$#{byte_size(value[:value])}\r\n#{value[:value]}\r\n"
      end
    end
  end

  def process(%{command: "RPUSH", args: [key, value]}) do
    existing_value = Agent.get(:key_value_store, fn data -> data[key] end)
    if existing_value == nil do
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: [value], ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length([value])}\r\n"
    else
      existing_list = existing_value[:value] || []
      new_list = List.insert_at(existing_list, -1, value)
      IO.puts("New list: #{inspect(new_list)}")
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length(new_list)}\r\n"
    end
  end

  def process(%{command: command, args: _args}) do
    IO.puts("Unknown command: #{command}")
    "-ERR unknown et dah '#{command}'\r\n"
  end

  # Catch-all for any other command format
  def process(command) do
    IO.puts("Invalid command format: #{inspect(command)}")
    "-ERR invalid command format\r\n"
  end
end
