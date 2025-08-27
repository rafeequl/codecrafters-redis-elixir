defmodule CommandProcessor do
  @moduledoc """
  Command processor for Redis commands
  """

  alias CodecraftersRedis.Logging

  def process(%{command: "COMMAND", args: []}) do
    # Return information about available commands
    # This is typically sent by Redis CLI when it first connects
    "*0\r\n"
  end

  def process(%{command: "COMMAND", args: ["DOCS"]}) do
    # Handle COMMAND DOCS - return empty array
    "*0\r\n"
  end

  @doc """
  Process PING command and return PONG response.

  ## Examples

      iex> CommandProcessor.process(%{command: "PING", args: []})
      "+PONG\\r\\n"
  """
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
        RESPFormatter.simple_string("-1")
      else
        if DateTime.diff(DateTime.utc_now(), value[:created_at], :millisecond) > value[:ttl] do
          Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
          RESPFormatter.null_bulk_string()
        else
          Logging.log_command_processing("get_with_ttl", [key], %{
            key: key,
            ttl_value: value[:ttl],
            created_at: value[:created_at]
          })
          RESPFormatter.bulk_string(value[:value])
        end
      end
    else
      if value == nil do
        RESPFormatter.null_bulk_string()
      else
        Logging.log_command_processing("get_without_ttl", [key], %{
          key: key,
          value_type: "no_ttl"
        })
        RESPFormatter.bulk_string(value[:value])
      end
    end
  end

  # process RPUSH with multiple values
  def process(%{command: "RPUSH", args: [key | values]}) do
    existing_value = Agent.get(:key_value_store, fn data -> data[key] end)
    if existing_value == nil do
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: values, ttl: nil, created_at: DateTime.utc_now()}) end)
      RESPFormatter.integer(length(values))
    else
      existing_list = existing_value[:value] || []
      # merge the existing list with values (which is a list)
      new_list = existing_list ++ values
      Logging.log_command_processing("rpush_list_updated", [key | values], %{
        key: key,
        existing_count: length(existing_list),
        new_values_count: length(values),
        final_count: length(new_list)
      })

      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      RESPFormatter.integer(length(new_list))
    end
  end

  # process LPUSH with multiple values
  def process(%{command: "LPUSH", args: [key | values]}) do
    existing_value = Agent.get(:key_value_store, fn data -> data[key] end)
    if existing_value == nil do
      # For new list, reverse the values to put first item at front
      reversed_values = Enum.reverse(values)
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: reversed_values, ttl: nil, created_at: DateTime.utc_now()}) end)
      RESPFormatter.integer(length(values))
    else
      existing_list = existing_value[:value] || []
      new_list = Enum.reverse(values) ++ existing_list
      Logging.log_command_processing("lpush_list_updated", [key | values], %{
        key: key,
        existing_count: length(existing_list),
        new_values_count: length(values),
        final_count: length(new_list)
      })
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      RESPFormatter.integer(length(new_list))
    end
  end

  # Process LRANGE and return the list of values
  def process(%{command: "LRANGE", args: [key, start, stop]}) do
    value = Agent.get(:key_value_store, fn data -> data[key] end)
    # check if value is present and is a list
    if value == nil do
      RESPFormatter.empty_array()
    else
      if is_list(value[:value]) do
        list = value[:value] || []
        start_idx = String.to_integer(start)
        stop_idx = String.to_integer(stop)

        # Handle negative indices (count from end)
        start_idx = if start_idx < 0, do: length(list) + start_idx, else: start_idx
        stop_idx = if stop_idx < 0, do: length(list) + stop_idx, else: stop_idx

        # Check if range is valid (start <= stop)
        if start_idx > stop_idx do
          RESPFormatter.empty_array()
        else
          # Check if both indices are out of bounds
          if start_idx >= length(list) do
            RESPFormatter.empty_array()
          else
            # Ensure indices are within bounds
            start_idx = max(0, min(start_idx, length(list) - 1))
            stop_idx = max(0, min(stop_idx, length(list) - 1))

            # Get the slice of the list
            slice = Enum.slice(list, start_idx..stop_idx)

            # Return as RESP array
            RESPFormatter.array(slice)
          end
        end
      else
        "*0\r\n"
      end
    end
  end

  def process(%{command: "LLEN", args: [key]}) do
    value = Agent.get(:key_value_store, fn data -> data[key] end)
    if value == nil do
      RESPFormatter.integer(0)
    else
      RESPFormatter.integer(length(value[:value]))
    end
  end

  def process(%{command: "LPOP", args: [key]}) do
    list = Agent.get(:key_value_store, fn data -> data[key] end)
    if list == nil do
      RESPFormatter.null_bulk_string()
    else
      first_item = hd(list[:value])
      new_list = tl(list[:value])
      Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
      RESPFormatter.bulk_string(first_item)
    end
  end

  def process(%{command: "LPOP", args: [key, count]}) do
    count_int = String.to_integer(count)
    if count_int > 0 do
      list = Agent.get(:key_value_store, fn data -> data[key] end)
      if list == nil do
        RESPFormatter.null_bulk_string()
      else
        items_to_pop = Enum.take(list[:value], count_int)
        new_list = list[:value] -- items_to_pop
        Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()}) end)
        RESPFormatter.array(items_to_pop)
      end
    else
      RESPFormatter.empty_array()
    end
  end

  def process(%{command: "FLUSHDB", args: []}) do
    Agent.update(:key_value_store, fn _ -> %{} end)
    RESPFormatter.simple_string("OK")
  end

  def process(%{command: command, args: _args}) do
    Logging.log_warning("Unknown command received", "unknown_command", %{
      command: command,
      command_type: "unrecognized"
    })
    "-ERR unknown et dah '#{command}'\r\n"
  end

  # Catch-all for any other command format
  def process(command) do
    Logging.log_warning("Invalid command format", "invalid_command_format", %{
      command: command,
      command_type: "malformed"
    })
    "-ERR invalid command format\r\n"
  end
end
