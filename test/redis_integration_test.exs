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

  # before each test, flush the database
  setup %{conn: conn} do
    # Clean up before test
    Redix.command(conn, ["FLUSHDB"])

    # Clean up after test as well
    on_exit(fn ->
      Redix.command(conn, ["FLUSHDB"])
    end)

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

  test "type command via Redix client", %{conn: conn} do
    Redix.command(conn, ["SET", "foo", "bar"])
    {:ok, response} = Redix.command(conn,  ["TYPE", "foo"])
    assert response == "string"
  end

  test "type command - non-existent key", %{conn: conn} do
    {:ok, response} = Redix.command(conn, ["TYPE", "non_existent_key"])
    assert response == "none"
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
    {:ok, lpush_response} =
      Redix.command(conn, ["LPUSH", "existing_list", "new_item1", "new_item2"])

    assert lpush_response == 3

    # Verify the list has all items in correct order
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "existing_list", "0", "-1"])
    assert lrange_response == ["new_item2", "new_item1", "original"]
  end

  test "rpush command - new list", %{conn: conn} do
    # Test RPUSH command creating a new list
    {:ok, rpush_response} =
      Redix.command(conn, ["RPUSH", "test_rlist", "item1", "item2", "item3"])

    assert rpush_response == 3

    # Verify the list was created with correct order (RPUSH adds to end)
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "test_rlist", "0", "-1"])
    assert lrange_response == ["item1", "item2", "item3"]
  end

  test "rpush command - existing list", %{conn: conn} do
    # First create a list
    {:ok, _} = Redix.command(conn, ["RPUSH", "existing_rlist", "original"])

    # Add more items to existing list
    {:ok, rpush_response} =
      Redix.command(conn, ["RPUSH", "existing_rlist", "new_item1", "new_item2"])

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

  test "blpop command - empty list block until item is added", %{conn: conn} do
    # Test BLPOP on empty list - should block until item is added
    parent = self()

    # Start BLPOP in a separate process
    _blpop_pid = spawn(fn ->
      case Redix.start_link(host: "localhost", port: 6379) do
        {:ok, blpop_conn} ->
          # Start BLPOP with a longer timeout
          case Redix.command(blpop_conn, ["BLPOP", "test_list", "1000"]) do
            {:ok, result} ->
              Redix.stop(blpop_conn)
              send(parent, {:blpop_result, result})
            {:error, error} ->
              Redix.stop(blpop_conn)
              send(parent, {:blpop_error, error})
          end
        {:error, error} ->
          send(parent, {:blpop_error, error})
      end
    end)

    # Wait for BLPOP to start and register
    # Process.sleep(50)

    # Add item to the list
    {:ok, _} = Redix.command(conn, ["RPUSH", "test_list", "test_item"])

    # Wait for BLPOP result
    result = receive do
      {:blpop_result, result} -> result
      {:blpop_error, error} -> flunk("BLPOP failed: #{inspect(error)}")
    after
      2000 -> flunk("BLPOP timed out waiting for result")
    end

    # Verify the result
    assert result == ["test_list", "test_item"]

    # Verify the item was removed from the list
    {:ok, lrange_response} = Redix.command(conn, ["LRANGE", "test_list", "0", "-1"])
    assert lrange_response == []
  end

  test "blpop command - timeout behavior", %{conn: conn} do
    # Test BLPOP timeout when no items are added
    start_time = System.monotonic_time(:millisecond)

    {:ok, result} = Redix.command(conn, ["BLPOP", "test_list_timeout", "0.5"])

    end_time = System.monotonic_time(:millisecond)
    elapsed_time = end_time - start_time

    # Should return nil after timeout
    assert result == nil
    # Should have taken at least 500ms (allowing for some overhead)
    assert elapsed_time >= 400
  end

  test "blpop race condition - multiple clients simultaneous", %{conn: conn} do
    # This test mimics the exact race condition from the logs:
    # - Client-1 and Client-2 call BLPOP simultaneously
    # - Client-3 calls RPUSH shortly after
    # - Only one client should get the item, others should block

    parent = self()
   _results = []

    # Start Client-1 BLPOP
    _client1_pid = spawn(fn ->
      case Redix.start_link(host: "localhost", port: 6379) do
        {:ok, client1_conn} ->
          case Redix.command(client1_conn, ["BLPOP", "race_test_list", "5"]) do
            {:ok, result} ->
              Redix.stop(client1_conn)
              send(parent, {:client1_result, result})
            {:error, error} ->
              Redix.stop(client1_conn)
              send(parent, {:client1_error, error})
          end
        {:error, error} ->
          send(parent, {:client1_error, error})
      end
    end)

    # Start Client-2 BLPOP (almost simultaneously)
    _client2_pid = spawn(fn ->
      case Redix.start_link(host: "localhost", port: 6379) do
        {:ok, client2_conn} ->
          case Redix.command(client2_conn, ["BLPOP", "race_test_list", "5"]) do
            {:ok, result} ->
              Redix.stop(client2_conn)
              send(parent, {:client2_result, result})
            {:error, error} ->
              Redix.stop(client2_conn)
              send(parent, {:client2_error, error})
          end
        {:error, error} ->
          send(parent, {:client2_error, error})
      end
    end)

    # Small delay to ensure both BLPOP clients are registered
    Process.sleep(10)

    # Client-3 RPUSH (this should wake up one of the waiting clients)
    {:ok, rpush_result} = Redix.command(conn, ["RPUSH", "race_test_list", "race_item"])
    assert rpush_result == 1

    # Collect results from both clients
    client1_result = receive do
      {:client1_result, result} -> {:ok, result}
      {:client1_error, error} -> {:error, error}
    after
      3000 -> {:error, :timeout}
    end

    client2_result = receive do
      {:client2_result, result} -> {:ok, result}
      {:client2_error, error} -> {:error, error}
    after
      3000 -> {:error, :timeout}
    end

    # Verify results
    case {client1_result, client2_result} do
      # Expected: One client gets the item, other times out
      {{:ok, ["race_test_list", "race_item"]}, {:error, :timeout}} ->
        # This is the correct behavior
        :ok
      {{:error, :timeout}, {:ok, ["race_test_list", "race_item"]}} ->
        # This is also correct behavior
        :ok
      # Unexpected: Both clients get responses (race condition)
      {{:ok, result1}, {:ok, result2}} ->
        flunk("Race condition detected! Both clients received responses: #{inspect(result1)}, #{inspect(result2)}")
      # Unexpected: Both clients timeout
      {{:error, :timeout}, {:error, :timeout}} ->
        flunk("Both clients timed out - RPUSH may not have woken up any clients")
      # Other unexpected combinations
      {result1, result2} ->
        flunk("Unexpected results: client1=#{inspect(result1)}, client2=#{inspect(result2)}")
    end

    # Verify the list is empty (item was consumed)
    {:ok, remaining_items} = Redix.command(conn, ["LRANGE", "race_test_list", "0", "-1"])
    assert remaining_items == []
  end

  test "blpop race condition - multiple items multiple clients", %{conn: conn} do
    # Test with multiple items to ensure proper FIFO behavior
    parent = self()

    # Start 3 BLPOP clients
    _clients = for i <- 1..3 do
      spawn(fn ->
        case Redix.start_link(host: "localhost", port: 6379) do
          {:ok, client_conn} ->
            case Redix.command(client_conn, ["BLPOP", "multi_race_list", "5"]) do
              {:ok, result} ->
                Redix.stop(client_conn)
                send(parent, {:client_result, i, result})
              {:error, error} ->
                Redix.stop(client_conn)
                send(parent, {:client_error, i, error})
            end
          {:error, error} ->
            send(parent, {:client_error, i, error})
        end
      end)
    end

    # Small delay to ensure all BLPOP clients are registered
    Process.sleep(20)

    # Add 2 items (should wake up 2 clients)
    {:ok, _} = Redix.command(conn, ["RPUSH", "multi_race_list", "item1"])
    {:ok, _} = Redix.command(conn, ["RPUSH", "multi_race_list", "item2"])

    # Collect results
    results = for i <- 1..3 do
      receive do
        {:client_result, client_id, result} -> {client_id, {:ok, result}}
        {:client_error, client_id, error} -> {client_id, {:error, error}}
      after
        3000 -> {i, {:timeout, :timeout}}
      end
    end

    # Verify exactly 2 clients got items and 1 timed out
    success_count = Enum.count(results, fn {_id, result} ->
      match?({:ok, ["multi_race_list", _]}, result)
    end)

    timeout_count = Enum.count(results, fn {_id, result} ->
      match?({:timeout, :timeout}, result)
    end)

    assert success_count == 2, "Expected 2 clients to get items, got #{success_count}. Results: #{inspect(results)}"
    assert timeout_count == 1, "Expected 1 client to timeout, got #{timeout_count}. Results: #{inspect(results)}"

    # Verify the list is empty
    {:ok, remaining_items} = Redix.command(conn, ["LRANGE", "multi_race_list", "0", "-1"])
    assert remaining_items == []
  end

  test "xadd command - new stream", %{conn: conn} do
    # Test XADD on new stream
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "new_stream", "1", "field1", "value1"])
    assert xadd_response == "1"
  end

  test "xadd command - duplicate id rejection", %{conn: conn} do
    # Add first entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "test_stream", "1-1", "field1", "value1"])
    assert xadd_response == "1-1"

    # Try to add entry with same ID - should be rejected
    {:error, %Redix.Error{message: error_message}} = Redix.command(conn, ["XADD", "test_stream", "1-1", "field2", "value2"])
    assert String.contains?(error_message, "ERR The ID specified in XADD is equal or smaller than the target stream top item")
  end

  test "xadd command - valid id progression", %{conn: conn} do
    # Add first entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream", "1-1", "field1", "value1"])
    assert xadd_response == "1-1"

    # Add entry with higher sequence number - should succeed
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream", "1-2", "field2", "value2"])
    assert xadd_response == "1-2"

    # Add entry with higher timestamp - should succeed
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream", "2-1", "field3", "value3"])
    assert xadd_response == "2-1"
  end

  test "xadd command - valid id progression with *", %{conn: conn} do
    # Add first entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk", "1-*", "field1", "value1"])
    assert xadd_response == "1-0"

    # Add entry with higher sequence number - should succeed
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk", "1-*", "field2", "value2"])
    assert xadd_response == "1-1"

    # Add more entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk", "1-*", "field3", "value3"])
    assert xadd_response == "1-2"

    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk", "1-*", "field4", "value4"])
    assert xadd_response == "1-3"

  end

  test "xadd command - valid id progression with 0-*", %{conn: conn} do
    # Add first entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk_0", "0-*", "field1", "value1"])
    assert xadd_response == "0-1"

    # Add entry with higher sequence number - should succeed
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk_0", "0-*", "field2", "value2"])
    assert xadd_response == "0-2"

    # addn second entry
    {:ok, xadd_response} = Redix.command(conn, ["XADD", "progression_stream_asterisk_0", "1-*", "field3", "value3"])
    assert xadd_response == "1-0"

  end
end
