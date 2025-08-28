defmodule CommandProcessor do
  @moduledoc """
  Command processor for Redis commands
  """

  alias CommandProcessor.AdminCommands
  alias CommandProcessor.CoreCommands
  alias CommandProcessor.StringCommands
  alias CommandProcessor.ListCommands

  def process(%{command: "PING", args: []}) do
    CoreCommands.ping(%{command: "PING", args: []})
  end

  def process(%{command: "ECHO", args: [message]}) do
    CoreCommands.echo(%{command: "ECHO", args: [message]})
  end

  def process(%{command: "TYPE", args: [key]}) do
    CoreCommands.type(%{command: "TYPE", args: [key]})
  end

  def process(%{command: "COMMAND", args: []}) do
    AdminCommands.command(%{command: "COMMAND", args: []})
  end

  def process(%{command: "COMMAND", args: ["DOCS"]}) do
    AdminCommands.command(%{command: "COMMAND", args: ["DOCS"]})
  end

  def process(%{command: "FLUSHDB", args: []}) do
    AdminCommands.flushdb(%{command: "FLUSHDB", args: []})
  end

  def process(%{command: "SET", args: [key, value]}) do
    StringCommands.set(%{command: "SET", args: [key, value]})
  end

  def process(%{command: "SET", args: [key, value, _, ttl]}) do
    StringCommands.set(%{command: "SET", args: [key, value, "PX", ttl]})
  end

  def process(%{command: "GET", args: [key]}) do
    StringCommands.get(%{command: "GET", args: [key]})
  end

  # process RPUSH with multiple values
  def process(%{command: "RPUSH", args: [key | values]}) do
    ListCommands.rpush(%{command: "RPUSH", args: [key | values]})
  end

  # process LPUSH with multiple values
  def process(%{command: "LPUSH", args: [key | values]}) do
    ListCommands.lpush(%{command: "LPUSH", args: [key | values]})
  end

  # Process LRANGE and return the list of values
  def process(%{command: "LRANGE", args: [key, start, stop]}) do
    ListCommands.lrange(%{command: "LRANGE", args: [key, start, stop]})
  end

  def process(%{command: "LLEN", args: [key]}) do
    ListCommands.llen(%{command: "LLEN", args: [key]})
  end

  def process(%{command: "LPOP", args: [key]}) do
    ListCommands.lpop(%{command: "LPOP", args: [key]})
  end

  def process(%{command: "LPOP", args: [key, count]}) do
    ListCommands.lpop(%{command: "LPOP", args: [key, count]})
  end

  def process(%{command: "BLPOP", args: [key, timeout]}) do
    ListCommands.blpop(%{command: "BLPOP", args: [key, timeout]})
  end

  def process(%{command: command, args: _args}) do
    "-ERR unknown command '#{command}'\r\n"
  end

  # Catch-all for any other command format
  def process(_command) do
    "-ERR invalid command format\r\n"
  end
end
