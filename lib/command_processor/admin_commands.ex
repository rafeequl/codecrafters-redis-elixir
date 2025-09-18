defmodule CommandProcessor.AdminCommands do
  @moduledoc """
  Handles administrative Redis commands like COMMAND and FLUSHDB.
  """

  alias Store
  alias RESPFormatter
  alias CommandProcessor.ListCommandsServer
  alias CommandProcessor.StreamCommandServer

  @doc """
  Handle COMMAND command - return information about available commands.
  """
  def command(%{command: "COMMAND", args: []}) do
    # Return information about available commands
    # This is typically sent by Redis CLI when it first connects
    "*0\r\n"
  end

  def command(%{command: "COMMAND", args: ["DOCS"]}) do
    # Handle COMMAND DOCS - return empty array
    "*0\r\n"
  end

  @doc """
  Handle FLUSHDB command - clear all data from the store.
  """
  def flushdb(%{command: "FLUSHDB", args: []}) do
    Store.clear()
    ListCommandsServer.flush_all()
    StreamCommandServer.flush_all()
    RESPFormatter.simple_string("OK")
  end
end
