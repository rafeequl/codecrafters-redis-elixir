defmodule CommandProcessor.StringCommands do
  @moduledoc """
  Handles Redis string commands like SET and GET.
  """

  alias Store
  alias RESPFormatter
  alias CodecraftersRedis.Logging

  @doc """
  Handle SET command - store a key-value pair.
  """
  def set(%{command: "SET", args: [key, value]}) do
    Store.put(key, %{value: value, ttl: nil})
    RESPFormatter.simple_string("OK")
  end

  def set(%{command: "SET", args: [key, value, _, ttl]}) do
    ttl_int = String.to_integer(ttl)
    Store.put(key, %{value: value, ttl: ttl_int, created_at: DateTime.utc_now()})
    RESPFormatter.simple_string("OK")
  end

  @doc """
  Handle GET command - retrieve a value by key with TTL checking.
  """
  def get(%{command: "GET", args: [key]}) do
    value = Store.get(key)

    # if ttl is not nil, check if the key has expired
    if value != nil and value[:ttl] != nil do
      # Special case: px 0 means expire immediately
      if value[:ttl] == 0 do
        Store.delete(key)
        RESPFormatter.simple_string("-1")
      else
        if DateTime.diff(DateTime.utc_now(), value[:created_at], :millisecond) > value[:ttl] do
          Store.delete(key)
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
end
