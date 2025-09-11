defmodule CommandProcessor.ListCommandsServer do
  use GenServer

  alias RESPFormatter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{lists: %{}, waiting_queues: %{}}}
  end

  # RPUSH - append values to the end of a list
  def rpush(key, values) do
    GenServer.call(__MODULE__, {:rpush, key, values})
  end

  # LPUSH - prepend values to the beginning of a list
  def lpush(key, values) do
    GenServer.call(__MODULE__, {:lpush, key, values})
  end

  # LPOP - remove and return the first element of a list
  def lpop(key) do
    GenServer.call(__MODULE__, {:lpop, key})
  end

  def llen(key) do
    GenServer.call(__MODULE__, {:llen, key})
  end

  # Clear all lists (for testing)
  def flush_all do
    GenServer.call(__MODULE__, :flush_all)
  end

  # LRANGE - return a range of elements from a list
  def lrange(key, start, stop) do
    GenServer.call(__MODULE__, {:lrange, key, start, stop})
  end

  # LPOP with count - remove and return multiple elements from the beginning
  def lpop(key, count) do
    GenServer.call(__MODULE__, {:lpop_count, key, count})
  end

  # BLPOP - block until an element is available to pop, timeout in seconds
  def blpop(key, timeout) do
    timeout_ms = parse_timeout(timeout)

    # Try to get an item immediately first
    case GenServer.call(__MODULE__, {:blpop_immediate, key}) do
      :empty ->
        # Register waiting client and wait for wakeup
        wait_for_wakeup(key, timeout_ms)
      result ->
        result
    end
  end

  defp wait_for_wakeup(key, timeout_ms, start_time \\ System.system_time(:millisecond)) do
    GenServer.call(__MODULE__, {:register_waiting_client, key, self()})

    remaining_time = calculate_remaining_time(timeout_ms, start_time)

    receive do
      {:item_available, ^key} ->
        # Item is available, try to pop it immediately
        case GenServer.call(__MODULE__, {:blpop_immediate, key}) do
          :empty ->
            # Another client got it first, continue waiting
            wait_for_wakeup(key, timeout_ms, start_time)
          result ->
            GenServer.call(__MODULE__, {:remove_waiting_client, key, self()})
            result
        end
    after remaining_time ->
      # Timeout reached, remove client from waiting queue
      GenServer.call(__MODULE__, {:remove_waiting_client, key, self()})
      RESPFormatter.null_array()
    end
  end

  defp calculate_remaining_time(:infinity, _start_time), do: :infinity
  defp calculate_remaining_time(timeout_ms, start_time) do
    elapsed_time = System.system_time(:millisecond) - start_time
    max(0, timeout_ms - elapsed_time)
  end

  defp waking_up_waiting_client(key, state) do
    waiting_clients = Map.get(state.waiting_queues, key, [])

    if length(waiting_clients) > 0 do
      IO.puts("Waking up waiting client")
      [oldest_client | remaining_clients] = waiting_clients

      # send wake-up message to oldest client
      send(oldest_client, {:item_available, key})

      # remove oldest client from waiting queue
      %{state | waiting_queues: Map.put(state.waiting_queues, key, remaining_clients)}
    else
      IO.puts("No waiting clients")
      state
    end
  end

  # GenServer callbacks
  def handle_call({:rpush, key, values}, _from, state) do
    existing_list = Map.get(state.lists, key, [])
    new_list = existing_list ++ values

    new_state = %{state | lists: Map.put(state.lists, key, new_list)}

    # wake up waiting clients
    updated_state = waking_up_waiting_client(key, new_state)
    IO.puts("Updated state after waking up clients: #{inspect(updated_state)}")


    {:reply, RESPFormatter.integer(length(new_list)), updated_state}
  end

  def handle_call({:lpush, key, values}, _from, state) do
    existing_list = Map.get(state.lists, key, [])
    new_list = Enum.reverse(values) ++ existing_list

    new_state = %{state | lists: Map.put(state.lists, key, new_list)}

    # wake up waiting clients
    updated_state = waking_up_waiting_client(key, new_state)
    IO.puts("Updated state after waking up clients: #{inspect(updated_state)}")

    {:reply, RESPFormatter.integer(length(new_list)), updated_state}
  end

  def handle_call({:lpop, key}, _from, state) do
    case Map.get(state.lists, key) do
      nil ->
        {:reply, RESPFormatter.null_bulk_string(), state}

      [] ->
        {:reply, RESPFormatter.null_bulk_string(), state}

      [first_item | remaining_items] ->
        new_state = %{state | lists: Map.put(state.lists, key, remaining_items)}
        {:reply, RESPFormatter.bulk_string(first_item), new_state}
    end
  end

  def handle_call({:llen, key}, _from, state) do
    length = Map.get(state.lists, key, []) |> length
    {:reply, RESPFormatter.integer(length), state}
  end

  def handle_call({:lrange, key, start_str, stop_str}, _from, state) do
    list = Map.get(state.lists, key, [])

    if list == [] do
      {:reply, RESPFormatter.empty_array(), state}
    else
      start_idx = String.to_integer(start_str)
      stop_idx = String.to_integer(stop_str)

      # Handle negative indices (count from end)
      start_idx = if start_idx < 0, do: length(list) + start_idx, else: start_idx
      stop_idx = if stop_idx < 0, do: length(list) + stop_idx, else: stop_idx

      # Check if range is valid (start <= stop)
      if start_idx > stop_idx do
        {:reply, RESPFormatter.empty_array(), state}
      else
        # Check if both indices are out of bounds
        if start_idx >= length(list) do
          {:reply, RESPFormatter.empty_array(), state}
        else
          # Ensure indices are within bounds
          start_idx = max(0, min(start_idx, length(list) - 1))
          stop_idx = max(0, min(stop_idx, length(list) - 1))

          # Get the slice of the list
          slice = Enum.slice(list, start_idx..stop_idx)

          # Return as RESP array
          {:reply, RESPFormatter.array(slice), state}
        end
      end
    end
  end

  def handle_call({:lpop_count, key, count_str}, _from, state) do
    count_int = String.to_integer(count_str)

    if count_int > 0 do
      list = Map.get(state.lists, key, [])

      if list == [] do
        {:reply, RESPFormatter.null_bulk_string(), state}
      else
        items_to_pop = Enum.take(list, count_int)
        new_list = list -- items_to_pop
        new_state = %{state | lists: Map.put(state.lists, key, new_list)}
        {:reply, RESPFormatter.array(items_to_pop), new_state}
      end
    else
      {:reply, RESPFormatter.empty_array(), state}
    end
  end

  def handle_call({:blpop_immediate, key}, _from, state) do
    list = Map.get(state.lists, key, [])

    if length(list) > 0 do
      # List has items, pop immediately
      [first_item | remaining_items] = list
      new_state = %{state | lists: Map.put(state.lists, key, remaining_items)}
      {:reply, RESPFormatter.array([key, first_item]), new_state}
    else
      # List is empty
      {:reply, :empty, state}
    end
  end

  def handle_call({:register_waiting_client, key, client_pid}, _from, state) do
    waiting_queue = Map.get(state.waiting_queues, key, [])
    new_waiting_queue = waiting_queue ++ [client_pid]
    new_state = %{state | waiting_queues: Map.put(state.waiting_queues, key, new_waiting_queue)}
    {:reply, "OK", new_state}
  end

  def handle_call({:remove_waiting_client, key, client_pid}, _from, state) do
    waiting_queue = Map.get(state.waiting_queues, key, [])
    new_waiting_queue = waiting_queue -- [client_pid]
    new_state = %{state | waiting_queues: Map.put(state.waiting_queues, key, new_waiting_queue)}
    {:reply, "OK", new_state}
  end

  def handle_call(:flush_all, _from, _state) do
    {:reply, "OK", %{lists: %{}, waiting_queues: %{}}}
  end


  # Helper function to parse timeout string to milliseconds
  defp parse_timeout(timeout) do
    if String.contains?(timeout, ".") do
      # Convert float to milliseconds (e.g., "0.5" -> 500ms)
      trunc(String.to_float(timeout) * 1000)
    else
      timeout_int = String.to_integer(timeout)
      if timeout_int == 0 do
        # timeout=0 means wait forever in Redis
        :infinity
      else
        # Convert integer to milliseconds (e.g., "1" -> 1000ms)
        timeout_int * 1000
      end
    end
  end


end
