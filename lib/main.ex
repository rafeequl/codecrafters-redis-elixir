defmodule Server do
  @moduledoc """
  Your implementation of a Redis server
  """

  use Application

  alias TcpServer

  def start(_type, _args) do
    # Start the TCP server (which will also start the Agent)
    {:ok, _pid} = TcpServer.start(nil, nil)

    {:ok, self()}
  end
end
