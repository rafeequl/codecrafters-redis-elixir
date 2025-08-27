defmodule RESPFormatter do
  @moduledoc """
  Formats RESP responses
  """

  @doc """
  Simple string response for OK, PONG, etc.
  """
  def simple_string(response) do
    "+" <> response <> "\r\n"
  end

  @doc """
  Bulk string response for strings, numbers, etc.
  """
  def bulk_string(response) do
    "$" <> Integer.to_string(byte_size(response)) <> "\r\n" <> response <> "\r\n"
  end

  @doc """
  Simple error response for errors
  """
  def error(response) do
    "-" <> response <> "\r\n"
  end

end
