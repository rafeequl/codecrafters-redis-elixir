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

  def xadd(stream_key, id, field_value_pairs) do
    case GenServer.call(__MODULE__, {:xadd, stream_key, id, field_value_pairs}) do
      "OK" ->
        RESPFormatter.bulk_string(id)

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
    Logger.debug("Existing stream: #{inspect(existing_stream)}")

    if existing_stream == [] do
      new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
      new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
      {:reply, "OK", new_state}
    else
      # Get the latest ID from existing stream
      latest_id = List.last(existing_stream).id

      with {:ok, id} <- validate_id_format(id),
           {:ok, id} <- validate_id_cant_be_zero(id),
           {:ok, id} <- validate_id_greater_than_existing_id(id, latest_id),
           {:ok, new_state} <- update_stream(stream_key, id, field_value_pairs, state) do
        Logger.debug("New state: #{inspect(new_state)}")
        {:reply, "OK", new_state}
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
      _ -> {:ok, id}
    end
  end

  defp validate_id_greater_than_existing_id(id, latest_id) do
    case id > latest_id do
      true ->
        {:ok, id}

      false ->
        {:error,
         "ERR The ID specified in XADD is equal or smaller than the target stream top item"}
    end
  end

  defp update_stream(stream_key, id, field_value_pairs, state) do
    existing_stream = Map.get(state.streams, stream_key, [])
    new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
    new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
    {:ok, new_state}
  end
end
