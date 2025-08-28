defmodule RespParser do
  @moduledoc """
  Simple RESP parser for basic commands
  """

  alias CodecraftersRedis.Logging

  def parse(data) do
    Logging.log_command_processing("resp_parsing_started", [data], %{
      data_size: byte_size(data),
      data_preview: String.slice(data, 0, 100)
    })

    # Split by \r\n and filter out empty strings and length indicators
    # the first part is the command. Make the command uppercase
    parts =
      data
      |> String.split("\r\n")
      |> Enum.filter(fn part ->
        part != "" and not String.starts_with?(part, "*") and not String.starts_with?(part, "$")
      end)
      |> List.update_at(0, fn part ->
        String.upcase(part)
      end)

    Logging.log_command_processing("resp_parsing_completed", parts, %{
      parts_count: length(parts),
      command: List.first(parts)
    })

    case parts do
      ["COMMAND"] ->
        [%{command: "COMMAND", args: []}]

      ["COMMAND", "DOCS"] ->
        [%{command: "COMMAND", args: ["DOCS"]}]

      ["PING"] ->
        [%{command: "PING", args: []}]

      ["ECHO", message] ->
        [%{command: "ECHO", args: [message]}]

      ["TYPE", key] ->
        [%{command: "TYPE", args: [key]}]

      ["SET", key, value] ->
        [%{command: "SET", args: [key, value]}]

      ["SET", key, value, px, ttl] ->
        [%{command: "SET", args: [key, value, px, ttl]}]

      ["GET", key] ->
        [%{command: "GET", args: [key]}]

      ["RPUSH", key | values] ->
        [%{command: "RPUSH", args: [key | values]}]

      ["LPUSH", key | values] ->
        [%{command: "LPUSH", args: [key | values]}]

      ["LRANGE", key, start, stop] ->
        [%{command: "LRANGE", args: [key, start, stop]}]

      ["LLEN", key] ->
        [%{command: "LLEN", args: [key]}]

      ["LPOP", key] ->
        [%{command: "LPOP", args: [key]}]

      ["LPOP", key, count] ->
        [%{command: "LPOP", args: [key, count]}]

      ["BLPOP", key, timeout] ->
        [%{command: "BLPOP", args: [key, timeout]}]

      ["BLPOP" | args] when length(args) >= 2 ->
        # Handle BLPOP with multiple lists: BLPOP list1 list2 ... timeout
        timeout = List.last(args)
        keys = Enum.drop(args, -1)
        [%{command: "BLPOP", args: keys ++ [timeout]}]

      ["FLUSHDB"] ->
        [%{command: "FLUSHDB", args: []}]

      _ ->
        Logging.log_warning("Unknown command received", "unknown_command", %{
          command_parts: parts,
          data_original: data
        })

        []
    end
  end
end
