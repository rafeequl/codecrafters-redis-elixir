defmodule CommandProcessor.ListCommands do
  @moduledoc """
  Handles Redis list commands like RPUSH, LPUSH, LRANGE, LLEN, LPOP, and BLPOP.
  """

  alias Store
  alias RESPFormatter
  alias CodecraftersRedis.Logging

  @doc """
  Handle RPUSH command - append values to the end of a list.
  """
  def rpush(%{command: "RPUSH", args: [key | values]}) do
    existing_value = Store.get(key)

    if existing_value == nil do
      Store.put(key, %{value: values, ttl: nil, created_at: DateTime.utc_now()})
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

      Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
      RESPFormatter.integer(length(new_list))
    end
  end

  @doc """
  Handle LPUSH command - prepend values to the beginning of a list.
  """
  def lpush(%{command: "LPUSH", args: [key | values]}) do
    existing_value = Store.get(key)

    if existing_value == nil do
      # For new list, reverse the values to put first item at front
      reversed_values = Enum.reverse(values)
      Store.put(key, %{value: reversed_values, ttl: nil, created_at: DateTime.utc_now()})
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

      Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
      RESPFormatter.integer(length(new_list))
    end
  end

  @doc """
  Handle LRANGE command - return a range of elements from a list.
  """
  def lrange(%{command: "LRANGE", args: [key, start, stop]}) do
    value = Store.get(key)
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

  @doc """
  Handle LLEN command - return the length of a list.
  """
  def llen(%{command: "LLEN", args: [key]}) do
    value = Store.get(key)

    if value == nil do
      RESPFormatter.integer(0)
    else
      RESPFormatter.integer(length(value[:value]))
    end
  end

  @doc """
  Handle LPOP command - remove and return the first element of a list.
  """
  def lpop(%{command: "LPOP", args: [key]}) do
    list = Store.get(key)

    if list == nil do
      RESPFormatter.null_bulk_string()
    else
      first_item = hd(list[:value])
      new_list = tl(list[:value])
      Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
      RESPFormatter.bulk_string(first_item)
    end
  end

  def lpop(%{command: "LPOP", args: [key, count]}) do
    count_int = String.to_integer(count)

    if count_int > 0 do
      list = Store.get(key)

      if list == nil do
        RESPFormatter.null_bulk_string()
      else
        items_to_pop = Enum.take(list[:value], count_int)
        new_list = list[:value] -- items_to_pop
        Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
        RESPFormatter.array(items_to_pop)
      end
    else
      RESPFormatter.empty_array()
    end
  end

  @doc """
  Handle BLPOP command - block until an element is available to pop.
  """
  def blpop(%{command: "BLPOP", args: [key, timeout]}) do
    IO.puts("DEBUG: BLPOP called with key=#{key}, timeout=#{timeout}")

    # Check if list exists and has items
    list = Store.get(key)

    if list != nil and length(list[:value]) > 0 do
      # List has items, pop immediately
      first_item = hd(list[:value])
      new_list = tl(list[:value])
      Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
      RESPFormatter.array([key, first_item])
    else
      # List is empty or doesn't exist - wait for item to be added
      # Timeout can be "1" or "1.0"
      timeout_int =
        if String.contains?(timeout, "."),
          do: String.to_float(timeout),
          else: String.to_integer(timeout)

      wait_for_item(key, timeout_int)
    end
  end

  # Private helper functions for blocking operations

  defp wait_for_item(key, timeout) do
    # For now, use a simple polling approach that's compatible with the current architecture
    # In a real Redis implementation, this would use proper blocking I/O
    if timeout == 0 do
      # Wait indefinitely - poll every 100ms
      wait_with_polling(key)
    else
      # Wait with timeout
      wait_with_timeout(key, timeout, 0)
    end
  end

  defp wait_with_polling(key) do
    # Simple polling approach for timeout = 0
    case Store.get(key) do
      nil ->
        # List doesn't exist, wait a bit and check again
        Process.sleep(100)
        wait_with_polling(key)

      list ->
        if length(list[:value]) > 0 do
          # Item is available, pop it
          first_item = hd(list[:value])
          new_list = tl(list[:value])
          Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
          RESPFormatter.array([key, first_item])
        else
          # List exists but is empty, wait a bit and check again
          Process.sleep(100)
          wait_with_polling(key)
        end
    end
  end

  defp wait_with_timeout(key, timeout, elapsed) do
    # Check if we've exceeded the timeout
    if elapsed >= timeout * 1000 do
      # Timeout reached, return nil
      RESPFormatter.null_bulk_string()
    else
      # Check if item was added
      case Store.get(key) do
        nil ->
          # List doesn't exist, wait a bit and check again
          Process.sleep(50)
          wait_with_timeout(key, timeout, elapsed + 50)

        list ->
          if length(list[:value]) > 0 do
            # Item was added, pop it
            first_item = hd(list[:value])
            new_list = tl(list[:value])
            Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
            RESPFormatter.array([key, first_item])
          else
            # List exists but is empty, wait a bit and check again
            Process.sleep(50)
            wait_with_timeout(key, timeout, elapsed + 50)
          end
      end
    end
  end
end
