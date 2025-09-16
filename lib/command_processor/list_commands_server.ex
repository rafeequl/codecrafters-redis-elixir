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
    # log timestamp when the blpop is called
    IO.puts(" ====> #{inspect(self())} - Blpop called at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

    timeout_ms = parse_timeout(timeout)

    # Try to get an item immediately first
    case GenServer.call(__MODULE__, {:blpop_atomic, key, self()}) do
      :empty ->
        # Register waiting client and wait for wakeup
        wait_for_wakeup(key, timeout_ms)

      result ->
        result
    end
  end

  # GenServer callbacks
  def handle_call({:rpush, key, values}, _from, state) do
    IO.puts(" ====> #{inspect(self())} - Rpush called with key: #{key} and values: #{inspect(values)} at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")
    existing_list = Map.get(state.lists, key, [])
    new_list = existing_list ++ values

    new_state = %{state | lists: Map.put(state.lists, key, new_list)}

    # Return immediately without waking up clients synchronously
    IO.puts("====> #{inspect(self())} - Updated state immediately: #{inspect(new_state)} at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

    # Wake up clients asynchronously after returning response
    GenServer.cast(__MODULE__, {:wake_up_clients, key})

    {:reply, RESPFormatter.integer(length(new_list)), new_state}
  end

  def handle_call({:lpush, key, values}, _from, state) do
    existing_list = Map.get(state.lists, key, [])
    new_list = Enum.reverse(values) ++ existing_list

    new_state = %{state | lists: Map.put(state.lists, key, new_list)}

    # Wake up waiting clients asynchronously to avoid blocking
    GenServer.cast(__MODULE__, {:wake_up_clients, key})
    IO.puts("Updated state after waking up clients: #{inspect(new_state)}")

    {:reply, RESPFormatter.integer(length(new_list)), new_state}
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

  def handle_call({:blpop_atomic, key, client_pid}, _from, state) do
    list = Map.get(state.lists, key, [])

    IO.puts(" ====> #{inspect(client_pid)} - #{inspect(list)} - blpop atomic called att #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

    if length(list) > 0 do
      IO.puts(" ====> #{inspect(client_pid)} - #{inspect(list)} - List has items, pop immediately and remove client from waiting queue")
      # List has items, pop immediately and remove client from waiting queue
      [first_item | remaining_items] = list
      new_state = %{state | lists: Map.put(state.lists, key, remaining_items)}

      # Remove this client from waiting queue if it was waiting
      updated_state = remove_waiting_client_from_state(new_state, key, client_pid)

      # Don't wake up the next client here - let RPUSH/LPUSH handle it
      final_state = updated_state

      IO.puts(" ====> #{inspect(client_pid)} - #{inspect(final_state)} - Final state after popping item at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

      {:reply, RESPFormatter.array([key, first_item]), final_state}
    else
      # To make it atomic, we need to register the client in the waiting queue
      updated_state = register_waiting_client(state, key, client_pid)

      {:reply, :empty, updated_state}
    end
  end

  def handle_call({:remove_waiting_client, key, client_pid}, _from, state) do
    new_state = remove_waiting_client_from_state(state, key, client_pid)
    {:reply, "OK", new_state}
  end

  def handle_call(:flush_all, _from, _state) do
    {:reply, "OK", %{lists: %{}, waiting_queues: %{}}}
  end

  def handle_cast({:wake_up_clients, key}, state) do
    # Wake up waiting clients asynchronously
    updated_state = waking_up_waiting_client(key, state)
    {:noreply, updated_state}
  end

  defp register_waiting_client(state, key, client_pid) do
    IO.puts(" ====> #{inspect(self())} - Registering waiting client #{inspect(client_pid)} at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")
    waiting_queue = Map.get(state.waiting_queues, key, [])
    new_waiting_queue = waiting_queue ++ [client_pid]
    new_state = %{state | waiting_queues: Map.put(state.waiting_queues, key, new_waiting_queue)}
    new_state
  end

  defp waking_up_waiting_client(key, state) do
    waiting_clients = Map.get(state.waiting_queues, key, [])

    if length(waiting_clients) > 0 do
      [oldest_client | remaining_clients] = waiting_clients
      IO.puts(" ====> Waking up waiting client #{inspect(oldest_client)} at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

      # send wake-up message to oldest client
      send(oldest_client, {:item_available, key})

      # remove oldest client from waiting queue
      %{state | waiting_queues: Map.put(state.waiting_queues, key, remaining_clients)}
    else
      IO.puts(" ====> No waiting clients")
      state
    end
  end

  defp remove_waiting_client_from_state(state, key, client_pid) do
    waiting_queue = Map.get(state.waiting_queues, key, [])
    new_waiting_queue = waiting_queue -- [client_pid]
    %{state | waiting_queues: Map.put(state.waiting_queues, key, new_waiting_queue)}
  end

  defp wait_for_wakeup(key, timeout_ms, start_time \\ System.system_time(:millisecond)) do
    IO.puts(" ====> Waiting for wakeup at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

    remaining_time = calculate_remaining_time(timeout_ms, start_time)

    receive do
      {:item_available, ^key} ->
        IO.puts(" ====> Item available at #{inspect(DateTime.utc_now() |> DateTime.to_unix(:millisecond))}")

        # Item is available, try to pop it atomically
        case GenServer.call(__MODULE__, {:blpop_atomic, key, self()}) do
          :empty ->
            # Another client got it first, continue waiting
            wait_for_wakeup(key, timeout_ms, start_time)

          result ->
            result
        end
    after
      remaining_time ->
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
