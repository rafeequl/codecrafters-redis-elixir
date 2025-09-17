defmodule CommandProcessor.StreamCommandServer do
  use GenServer

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
    if existing_stream == [] do
      new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
      new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
      {:reply, "OK", new_state}
    else
      existing_id = Enum.map(existing_stream, fn x -> x.id end)

      cond do
        id > Enum.max(existing_id) ->
          new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
          new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
          {:reply, "OK", new_state}
        id == "0-0" ->
          {:reply, "ERR The ID specified in XADD must be greater than 0-0", state}
        id <= Enum.max(existing_id) ->
          {:reply, "ERR The ID specified in XADD is equal or smaller than the target stream top item", state}
        true ->
          {:reply, "ERR The ID specified in XADD is equal or smaller than #{id}", state}
      end
    end
  end

  def handle_call({:exists, stream_key}, _from, state) do
    {:reply, Map.has_key?(state.streams, stream_key), state}
  end
end
