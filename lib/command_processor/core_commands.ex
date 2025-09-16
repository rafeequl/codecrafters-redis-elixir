defmodule CommandProcessor.CoreCommands do
  @moduledoc """
  Handles core Redis commands like PING and ECHO.
  These are simple commands that don't involve data storage or complex logic.
  """

  alias RESPFormatter
  alias Store
  alias CommandProcessor.StreamCommandServer
  @doc """
  Handle PING command - return PONG response.

  ## Examples

      iex> CoreCommands.ping(%{command: "PING", args: []})
      "+PONG\\r\\n"
  """
  def ping(%{command: "PING", args: []}) do
    RESPFormatter.simple_string("PONG")
  end

  @doc """
  Handle ECHO command - return the message as-is.

  ## Examples

      iex> CoreCommands.echo(%{command: "ECHO", args: ["hello"]})
      "$5\\r\\nhello\\r\\n"
  """
  def echo(%{command: "ECHO", args: [message]}) do
    RESPFormatter.bulk_string(message)
  end

  def type(%{command: "TYPE", args: [message]}) do
    # we need to check to Store as well as the StreamCommandServer
    # if it exists in the StreamCommandServer, return "stream"
    # if not then check the Store
    # if it exists in the Store, return "string"
    # if not then return "none"

    cond do
      StreamCommandServer.exists?(message) ->
        RESPFormatter.simple_string("stream")

      Store.get(message) != nil ->
        RESPFormatter.simple_string("string")

      true ->
        RESPFormatter.simple_string("none")
    end

  end
end
