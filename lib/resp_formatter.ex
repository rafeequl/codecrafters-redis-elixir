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
  Null bulk string response for nil/null values
  """
  def null_bulk_string do
    "$-1\r\n"
  end

  @doc """
  Empty array response for empty lists/arrays
  """
  def empty_array do
    "*0\r\n"
  end

  @doc """
  Array response header with count of elements
  """
  def array_header(count) do
    "*#{count}\r\n"
  end

  @doc """
  Format a list of items as an array response
  """
  def array(items) when is_list(items) do
    array_header(length(items)) <>
      Enum.map_join(items, "", fn item ->
        bulk_string(item)
      end)
  end

  @doc """
  Integer response for numbers
  """
  def integer(response) do
    ":" <> Integer.to_string(response) <> "\r\n"
  end

  @doc """
  Simple error response for errors
  """
  def error(response) do
    "-" <> response <> "\r\n"
  end

end
