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
      _ ->
        RESPFormatter.error("Error adding to stream")
    end
  end

  def handle_call({:xadd, stream_key, id, field_value_pairs}, _from, state) do
    existing_stream = Map.get(state.streams, stream_key, [])
    new_stream = existing_stream ++ [%{id: id, field_value_pairs: field_value_pairs}]
    new_state = %{state | streams: Map.put(state.streams, stream_key, new_stream)}
    {:reply, "OK", new_state}
  end

  def handle_call({:exists, stream_key}, _from, state) do
    {:reply, Map.has_key?(state.streams, stream_key), state}
  end
end
