defmodule RespParser do
  @moduledoc """
  Simple RESP parser for basic commands
  """

  def parse(data) do
    IO.puts("Raw data: #{inspect(data)}")

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

    IO.puts("Parsed parts: #{inspect(parts)}")

    case parts do
      ["COMMAND"] ->
        [%{command: "COMMAND", args: []}]

      ["COMMAND", "DOCS"] ->
        [%{command: "COMMAND", args: ["DOCS"]}]

      ["PING"] ->
        [%{command: "PING", args: []}]

      ["ECHO", message] ->
        [%{command: "ECHO", args: [message]}]

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

      _ ->
        IO.puts("Unknown command: #{inspect(parts)}")
        []
    end
  end
end
