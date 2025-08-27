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
    RESPFormatter.simple_string("PONG")
  end

  def process(%{command: "ECHO", args: [message]}) do
    RESPFormatter.bulk_string(message)
  end

  def process(%{command: "SET", args: [key, value]}) do
    Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: value, ttl: nil}) end)
    RESPFormatter.simple_string("OK")
  end

  def process(%{command: "SET", args: [key, value, _, ttl]}) do
    ttl_int = String.to_integer(ttl)

    Agent.update(:key_value_store, fn data ->
      Map.put(data, key, %{value: value, ttl: ttl_int, created_at: DateTime.utc_now()})
    end)

    RESPFormatter.simple_string("OK")
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

  # process RPUSH with multiple values
  def process(%{command: "RPUSH", args: [key | values]}) do
    existing_value = Agent.get(:key_value_store, fn data -> data[key] end)
    if existing_value == nil do
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: values, ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length(values)}\r\n"
    else
      existing_list = existing_value[:value] || []
      # merge the existing list with values (which is a list)
      new_list = existing_list ++ values
      IO.puts("New list: #{inspect(new_list)}")

      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length(new_list)}\r\n"
    end
  end

  # process LPUSH with multiple values
  def process(%{command: "LPUSH", args: [key | values]}) do
    existing_value = Agent.get(:key_value_store, fn data -> data[key] end)
    if existing_value == nil do
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: values, ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length(Enum.reverse(values))}\r\n"
    else
      existing_list = existing_value[:value] || []
      new_list = Enum.reverse(values) ++ existing_list
      IO.puts("New list: #{inspect(new_list)}")
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      ":#{length(new_list)}\r\n"
    end
  end

  # Process LRANGE and return the list of values
  def process(%{command: "LRANGE", args: [key, start, stop]}) do
    value = Agent.get(:key_value_store, fn data -> data[key] end)
    # check if value is present and is a list
    if value == nil do
      "*0\r\n"
    else
      if is_list(value[:value]) do
        list = value[:value] || []
        start_idx = String.to_integer(start)
        stop_idx = String.to_integer(stop)

        # Handle negative indices (count from end)
        start_idx = if start_idx < 0, do: length(list) + start_idx, else: start_idx
        stop_idx = if stop_idx < 0, do: length(list) + stop_idx, else: stop_idx

        # Ensure indices are within bounds
        start_idx = max(0, min(start_idx, length(list) - 1))
        stop_idx = max(0, min(stop_idx, length(list) - 1))

        # Get the slice of the list
        slice = Enum.slice(list, start_idx..stop_idx)

        # Return as RESP array
        "*#{length(slice)}\r\n" <>
          Enum.map_join(slice, "", fn item ->
            "$#{byte_size(item)}\r\n#{item}\r\n"
          end)
      else
        "*0\r\n"
      end
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
