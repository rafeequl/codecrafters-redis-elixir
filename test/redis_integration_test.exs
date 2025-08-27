defmodule RedisIntegrationTest do
  @moduledoc """
  Real integration tests for Redis server using Redix client.
  Starts the server and tests via proper Redis client.
  """

  use ExUnit.Case, async: false

  # Start the actual Redis server before testing
  setup_all do
    # Start the Redis server
    {:ok, _pid} = Server.start(nil, nil)

    # Give it time to start up
    Process.sleep(200)

    # Start Redix connection
    {:ok, conn} = Redix.start_link(host: "localhost", port: 6379)

    {:ok, conn: conn}
  end

  # after each test, flush the database
  setup %{conn: conn} do
    Redix.command(conn, ["FLUSHDB"])
    :ok
  end

  test "ping command via Redix client", %{conn: conn} do
    # Send PING command using Redix
    {:ok, response} = Redix.command(conn, ["PING"])

    # Verify the response - Redix decodes RESP format to raw value
    assert response == "PONG"
  end

  test "echo command via Redix client", %{conn: conn} do
    # Send ECHO command using Redix
    {:ok, response} = Redix.command(conn, ["ECHO", "hello"])

    # Verify the response - Redix decodes RESP format to raw value
    assert response == "hello"
  end

  test "set and get commands - found scenario", %{conn: conn} do
    # Test SET command
    {:ok, set_response} = Redix.command(conn, ["SET", "test_key", "test_value"])
    assert set_response == "OK"

    # Test GET command - should find the value
    {:ok, get_response} = Redix.command(conn, ["GET", "test_key"])
    assert get_response == "test_value"
  end

  test "get command - not found scenario", %{conn: conn} do
    # Test GET command for non-existent key
    {:ok, get_response} = Redix.command(conn, ["GET", "non_existent_key"])
    assert get_response == nil
  end

  test "lpush command - new list", %{conn: conn} do
    # Test LPUSH command creating a new list
    {:ok, lpush_response} = Redix.command(conn, ["LPUSH", "test_list", "item1", "item2", "item3"])
    assert lpush_response == 3

    # Verify the list was created with correct order (LPUSH adds to front)
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "test_list", "0", "-1"])
    assert lrange_response == ["item3", "item2", "item1"]
  end

  test "lpush command - existing list", %{conn: conn} do
    # First create a list
    {:ok, _} = Redix.command(conn, ["LPUSH", "existing_list", "original"])

    # Add more items to existing list
    {:ok, lpush_response} = Redix.command(conn, ["LPUSH", "existing_list", "new_item1", "new_item2"])
    assert lpush_response == 3

    # Verify the list has all items in correct order
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "existing_list", "0", "-1"])
    assert lrange_response == ["new_item2", "new_item1", "original"]
  end

  test "rpush command - new list", %{conn: conn} do
    # Test RPUSH command creating a new list
    {:ok, rpush_response} = Redix.command(conn, ["RPUSH", "test_rlist", "item1", "item2", "item3"])
    assert rpush_response == 3

    # Verify the list was created with correct order (RPUSH adds to end)
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "test_rlist", "0", "-1"])
    assert lrange_response == ["item1", "item2", "item3"]
  end

  test "rpush command - existing list", %{conn: conn} do
    # First create a list
    {:ok, _} = Redix.command(conn, ["RPUSH", "existing_rlist", "original"])

    # Add more items to existing list
    {:ok, rpush_response} = Redix.command(conn, ["RPUSH", "existing_rlist", "new_item1", "new_item2"])
    assert rpush_response == 3

    # Verify the list has all items in correct order
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "existing_rlist", "0", "-1"])
    assert lrange_response == ["original", "new_item1", "new_item2"]
  end

  test "lrange command - full list", %{conn: conn} do
    # Create a list with 5 items
    {:ok, _} = Redix.command(conn, ["RPUSH", "range_list", "a", "b", "c", "d", "e"])

    # Get full list
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "range_list", "0", "-1"])
    assert lrange_response == ["a", "b", "c", "d", "e"]
  end

  test "lrange command - partial list", %{conn: conn} do
    # Create a list with 5 items
    {:ok, _} = Redix.command(conn, ["RPUSH", "partial_list", "a", "b", "c", "d", "e"])

    # Get partial list (index 1 to 3)
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "partial_list", "1", "3"])
    assert lrange_response == ["b", "c", "d"]
  end

  test "lrange command - negative indices", %{conn: conn} do
    # Create a list with 5 items
    {:ok, _} = Redix.command(conn, ["RPUSH", "negative_list", "a", "b", "c", "d", "e"])

    # Get last 3 items using negative indices
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "negative_list", "-3", "-1"])
    assert lrange_response == ["c", "d", "e"]
  end

  test "lrange command - not found list", %{conn: conn} do
    # Test LRANGE on non-existent list
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "non_existent_list", "0", "-1"])
    assert lrange_response == []
  end

  test "lrange command - empty range", %{conn: conn} do
    # Create a list
    {:ok, _} = Redix.command(conn, ["RPUSH", "empty_range_list", "a", "b", "c"])

    # Test LRANGE with invalid range (start > end)
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "empty_range_list", "5", "10"])
    assert lrange_response == []
  end

  test "llen command - empty list", %{conn: conn} do
    # Test LLEN on empty list
    {:ok, llen_response} = Redix.command(conn, ["LLEN", "empty_list"])
    assert llen_response == 0
  end

  test "llen command - non-empty list", %{conn: conn} do
    # Test LLEN on non-empty list
    {:ok, _} = Redix.command(conn, ["RPUSH", "non_empty_list", "item1", "item2", "item3"])
    {:ok, llen_response} = Redix.command(conn, ["LLEN", "non_empty_list"])
    assert llen_response == 3
  end

  test "lpop command - empty list", %{conn: conn} do
    # Test LPOP on empty list
    {:ok, lpop_response} = Redix.command(conn, ["LPOP", "empty_list"])
    assert lpop_response == nil
  end

  test "lpop command - non-empty list", %{conn: conn} do
    # Test LPOP on non-empty list
    {:ok, _} = Redix.command(conn, ["RPUSH", "non_empty_list", "item1", "item2", "item3"])
    {:ok, lpop_response} = Redix.command(conn, ["LPOP", "non_empty_list"])
    assert lpop_response == "item1"
  end

  test "lpop command - non-empty list remove item", %{conn: conn} do
    # Test LPOP on non-empty list
    {:ok, _} = Redix.command(conn, ["RPUSH", "non_empty_list", "item1", "item2", "item3"])
    {:ok, _} = Redix.command(conn, ["LPOP", "non_empty_list"])

    # Test the remaining list
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "non_empty_list", "0", "-1"])
    assert lrange_response == ["item2", "item3"]
  end

  test "lpop command - non-empty list with multiple items", %{conn: conn} do
    # Test LPOP on non-empty list
    {:ok, _} = Redix.command(conn, ["RPUSH", "non_empty_list", "item1", "item2", "item3"])
    {:ok, _} = Redix.command(conn, ["LPOP", "non_empty_list", "2"])


    # Test the remaining list
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "non_empty_list", "0", "-1"])
    assert lrange_response == ["item3"]
  end

end
