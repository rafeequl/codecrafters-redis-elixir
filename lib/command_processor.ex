defmodule CommandProcessor do
  @moduledoc """
  Command processor for Redis commands
  """

  @doc """
  Process a command and return the RESP response
  """
  def process(%{command: "PING", args: []}) do
    "+PONG\r\n"
  end

  def process(%{command: "ECHO", args: [message]}) do
    "$#{byte_size(message)}\r\n#{message}\r\n"
  end

  def process(%{command: "SET", args: [key, value]}) do
    Agent.update(:key_value_store, fn data -> Map.put(data, key, %{value: value, ttl: nil}) end)
    "+OK\r\n"
  end

  def process(%{command: "SET", args: [key, value, _, ttl]}) do
    ttl_int = String.to_integer(ttl)

    Agent.update(:key_value_store, fn data ->
      Map.put(data, key, %{value: value, ttl: ttl_int, created_at: DateTime.utc_now()})
    end)

    "+OK\r\n"
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

  def process(%{command: command, args: _args}) do
    IO.puts("Unknown command: #{command}")
    "-ERR unknown command '#{command}'\r\n"
  end
end
