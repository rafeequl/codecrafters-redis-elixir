defmodule RespParser do
  @moduledoc """
  Simple RESP parser for basic commands
  """



  def parse(data) do
    IO.puts("Raw data: #{inspect(data)}")

    # Split by \r\n and filter out empty strings and length indicators
    parts = data
            |> String.split("\r\n")
            |> Enum.filter(fn part ->
              part != "" and not String.starts_with?(part, "*") and not String.starts_with?(part, "$")
            end)

    IO.puts("Parsed parts: #{inspect(parts)}")

    case parts do
      ["PING"] -> [%{command: "PING", args: []}]
      ["ECHO", message] -> [%{command: "ECHO", args: [message]}]
      ["SET", key, value] -> [%{command: "SET", args: [key, value]}]
      ["SET", key, value, px, ttl] -> [%{command: "SET", args: [key, value, px, ttl]}]
      ["GET", key] -> [%{command: "GET", args: [key]}]
      _ ->
        IO.puts("Unknown command: #{inspect(parts)}")
        []
    end
  end
end
