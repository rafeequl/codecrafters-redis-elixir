defmodule RedisIntegrationTest do
  @moduledoc """
  Real integration tests for Redis server using Redix client.
  Starts the server and tests via proper Redis client.
  """

  use ExUnit.Case, async: false

  # Start the actual Redis server before testing
  setup do
    # Start the Redis server
    {:ok, _pid} = Server.start(nil, nil)

    # Give it time to start up
    Process.sleep(200)

    # Start Redix connection
    {:ok, conn} = Redix.start_link(host: "localhost", port: 6379)

    {:ok, conn: conn}
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
end
