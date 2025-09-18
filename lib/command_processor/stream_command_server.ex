defmodule CommandProcessor.StreamCommandServer do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{streams: %{}}}
  end

  def exists?(stream_key) do
    GenServer.call(__MODULE__, {:exists, stream_key})
  end

  def flush_all do
    GenServer.call(__MODULE__, :flush_all)
  end

  def xadd(stream_key, id, field_value_pairs) do
    case GenServer.call(__MODULE__, {:xadd, stream_key, id, field_value_pairs}) do
      {"OK", processed_id} ->
        RESPFormatter.bulk_string(processed_id)

      error_message when is_binary(error_message) ->
        RESPFormatter.error(error_message)

      _ ->
        RESPFormatter.error("Unknown error occurred")
    end
  end

  def handle_call({:xadd, stream_key, id, field_value_pairs}, _from, state) do
    # validate if id is a valid id
    # valid id is id that is equals or greater than exisiting id
    existing_stream = Map.get(state.streams, stream_key, [])

    if existing_stream == [] do
      # For new streams, still need to process IDs with *
      case generate_sequence_number(id, "0-0") do
        {:ok, processed_id} ->
          new_stream = existing_stream ++ [%{id: processed_id, field_value_pairs: field_value_pairs}]
          new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
          {:reply, {"OK", processed_id}, new_state}
        {:error, error_message} ->
          {:reply, error_message, state}
      end
    else
      # Get the latest ID from existing stream
      latest_id = List.last(existing_stream).id

      with {:ok, id} <- validate_id_format(id),
           {:ok, id} <- validate_id_cant_be_zero(id),
           {:ok, id} <- validate_id_greater_than_existing_id(id, latest_id),
           {:ok, processed_id} <- generate_sequence_number(id, latest_id),
           {:ok, new_state} <- update_stream(stream_key, processed_id, field_value_pairs, state) do
        Logger.debug("New state: #{inspect(new_state)}")
        {:reply, {"OK", processed_id}, new_state}
      else
        {:error, error_message} ->
          Logger.debug("Error: #{inspect(error_message)}")
          {:reply, error_message, state}
      end
    end
  end

  def handle_call({:exists, stream_key}, _from, state) do
    {:reply, Map.has_key?(state.streams, stream_key), state}
  end

  def handle_call(:flush_all, _from, _state) do
    {:reply, "OK", %{streams: %{}}}
  end

  # The logic to process xadd is like this:
  # 1. Parse the id
  # Validation scoped by id :
  # 2. validate the format (valid format is timestamp-sequence_number or timestamp-*)
  # 3. validate if timestamp and sequence number should be greater than 0
  # 4. validate if sequence number should be greater than exisiting sequence number if timestamp is the same
  # Auto generate sequence number if it is *
  # 5. if format is timestamp-*, auto generate sequence number based on existing sequence number

  defp validate_id_format(id) do
    case Regex.match?(~r/^\d+-\d+$|^\d+-\*$/, id) do
      true ->
        {:ok, id}

      false ->
        {:error,
         "ERR The ID specified in XADD must be in the format timestamp-sequence_number or timestamp-*"}
    end
  end

  defp validate_id_cant_be_zero(id) do
    case id do
      "0-0" -> {:error, "ERR The ID specified in XADD must be greater than 0-0"}
      "0-*" -> {:ok, id}  # Allow 0-* for new streams
      _ -> {:ok, id}
    end
  end

  defp validate_id_greater_than_existing_id(id, latest_id) do
    # If the ID contains *, we'll handle it in generate_sequence_number
    case String.contains?(id, "*") do
      true ->
        {:ok, id}
      false ->
        case compare_ids(id, latest_id) do
          :gt ->
            {:ok, id}

          _ ->
            {:error,
             "ERR The ID specified in XADD is equal or smaller than the target stream top item"}
        end
    end
  end

  defp compare_ids(id1, id2) do
    [ts1, seq1] = String.split(id1, "-")
    [ts2, seq2] = String.split(id2, "-")

    # Handle case where seq1 is "*" - it should be considered greater
    case {seq1, seq2} do
      {"*", _} -> :gt  # Any ID with * is considered greater
      {_, "*"} -> :lte # But if comparing against *, it's less
      _ ->
        {timestamp1, seq_num1} = {String.to_integer(ts1), String.to_integer(seq1)}
        {timestamp2, seq_num2} = {String.to_integer(ts2), String.to_integer(seq2)}

        cond do
          timestamp1 > timestamp2 -> :gt
          timestamp1 == timestamp2 and seq_num1 > seq_num2 -> :gt
          true -> :lte
        end
    end
  end

  defp generate_sequence_number(id, latest_id) do
    case Regex.match?(~r/^\d+-\*$/, id) do
      true ->
        # Extract timestamp from the input id
        [timestamp, _] = String.split(id, "-")
        [latest_timestamp, latest_sequence_str] = String.split(latest_id, "-")

        # Check if this is a new timestamp
        if timestamp != latest_timestamp do
          # New timestamp - start sequence from 0
          result = "#{timestamp}-0"
          {:ok, result}
        else
          # Same timestamp - increment sequence
          case Integer.parse(latest_sequence_str) do
            {latest_sequence_number, ""} ->
              new_sequence_number = case latest_sequence_number do
                # For new streams (when latest_id is "0-0"), start from 1 for timestamp 0
                0 when latest_id == "0-0" and timestamp == "0" -> 1
                # For all other cases, increment by 1
                _ -> latest_sequence_number + 1
              end
              result = "#{timestamp}-#{new_sequence_number}"
              {:ok, result}
            _ ->
              {:error, "Invalid sequence number in latest_id: #{latest_id}"}
          end
        end
      false ->
        {:ok, id}
    end
  end

  defp update_stream(stream_key, id, field_value_pairs, state) do
    existing_stream = Map.get(state.streams, stream_key, [])
    new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
    new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
    {:ok, new_state}
  end
end
