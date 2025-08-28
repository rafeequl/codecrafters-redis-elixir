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
      # Check if any clients are waiting for this key
      wake_up_waiting_clients(key)
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
      # Check if any clients are waiting for this key
      wake_up_waiting_clients(key)
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
      # Check if any clients are waiting for this key
      wake_up_waiting_clients(key)
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
      # Check if any clients are waiting for this key
      wake_up_waiting_clients(key)
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
    # Check if list exists and has items
    list = Store.get(key)

    if list != nil and length(list[:value]) > 0 do
      # List has items, pop immediately
      first_item = hd(list[:value])
      new_list = tl(list[:value])
      Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
      RESPFormatter.array([key, first_item])
    else
      # List is empty - add this client to waiting queue
      add_to_waiting_queue(key, self())

      # Wait for wakeup instead of polling
      timeout_int = parse_timeout(timeout)
      wait_for_wakeup(key, timeout_int)
    end
  end

  # NEW: Helper functions for waiting queue management
  # Use a simple map stored in the module to share waiting queues across processes
  @waiting_queues :waiting_queues

  defp ensure_waiting_queues_table do
    case :ets.info(@waiting_queues) do
      :undefined ->
        :ets.new(@waiting_queues, [:set, :public, :named_table])
      _ ->
        @waiting_queues
    end
  end

  defp add_to_waiting_queue(key, client_pid) do
    table = ensure_waiting_queues_table()
    current_queue = case :ets.lookup(table, key) do
      [{^key, queue}] -> queue
      [] -> []
    end
    new_queue = [client_pid | current_queue]
    :ets.insert(table, {key, new_queue})
  end

  defp get_waiting_queue(key) do
    table = ensure_waiting_queues_table()
    case :ets.lookup(table, key) do
      [{^key, queue}] -> queue
      [] -> []
    end
  end

  defp remove_from_waiting_queue(key) do
    table = ensure_waiting_queues_table()
    case :ets.lookup(table, key) do
      [{^key, queue}] ->
        case queue do
          [] -> :ok
          [_oldest_client | remaining_clients] ->
            :ets.insert(table, {key, remaining_clients})
            :ok
        end
      [] -> :ok
    end
  end

  # Remove a specific client from the waiting queue (for timeouts)
  defp remove_client_from_waiting_queue(key, client_pid) do
    table = ensure_waiting_queues_table()
    case :ets.lookup(table, key) do
      [{^key, queue}] ->
        filtered_queue = Enum.reject(queue, fn pid -> pid == client_pid end)
        :ets.insert(table, {key, filtered_queue})
      [] -> :ok
    end
  end

  defp wait_for_wakeup(key, timeout_ms) do
    receive do
      {:item_available, ^key} ->
        # Item is available, pop it immediately
        list = Store.get(key)
        if list != nil and length(list[:value]) > 0 do
          first_item = hd(list[:value])
          new_list = tl(list[:value])
          Store.put(key, %{value: new_list, ttl: nil, created_at: DateTime.utc_now()})
          RESPFormatter.array([key, first_item])
        else
          # Something went wrong, return nil
          RESPFormatter.null_bulk_string()
        end
    after timeout_ms ->
      # Timeout reached, remove self from waiting queue
      remove_client_from_waiting_queue(key, self())
      RESPFormatter.null_bulk_string()
    end
  end

  defp parse_timeout(timeout) do
    if String.contains?(timeout, ".") do
      # Convert float to milliseconds (e.g., "0.5" -> 500ms)
      trunc(String.to_float(timeout) * 1000)
    else
      # Convert integer to milliseconds (e.g., "1" -> 1000ms)
      String.to_integer(timeout) * 1000
    end
  end

    # NEW: Wake up the oldest waiting client when items are added
  defp wake_up_waiting_clients(key) do
    waiting_clients = get_waiting_queue(key)
    if length(waiting_clients) > 0 do
      # Wake up the oldest waiting client (first in queue)
      oldest_waiting_client = hd(waiting_clients)
      Process.send(oldest_waiting_client, {:item_available, key}, [])

      # Remove that client from waiting queue
      remove_from_waiting_queue(key)
    end
  end


end
