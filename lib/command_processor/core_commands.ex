defmodule CommandProcessor.CoreCommands do
  @moduledoc """
  Handles core Redis commands like PING and ECHO.
  These are simple commands that don't involve data storage or complex logic.
  """

  alias RESPFormatter

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
end
