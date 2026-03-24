defmodule Relayixir.Proxy.WebSocket.BridgeTest do
  use ExUnit.Case

  alias Relayixir.Proxy.WebSocket.Bridge
  alias Relayixir.Proxy.WebSocket.Frame
  alias Relayixir.Proxy.Upstream

  @moduletag :integration

  setup do
    # Start a WebSocket echo upstream
    {:ok, server_pid} = Bandit.start_link(plug: Relayixir.TestWsRouter, port: 0)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)

    upstream = %Upstream{
      scheme: :http,
      host: "127.0.0.1",
      port: port,
      path_prefix_rewrite: "/ws",
      connect_timeout: 5_000,
      request_timeout: 60_000,
      websocket?: true,
      host_forward_mode: :preserve,
      metadata: %{}
    }

    on_exit(fn ->
      try do
        ThousandIsland.stop(server_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    %{upstream: upstream, port: port}
  end

  test "starts bridge and transitions to :open state", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)

    # Give the bridge time to connect
    Process.sleep(200)

    # The bridge should be alive and in :open state
    assert Process.alive?(bridge_pid)

    # Clean up
    Bridge.downstream_closed(bridge_pid, 1000, "test done")
    Process.sleep(100)
  end

  test "relays text frame from downstream to upstream and gets echo back", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    # Send a text frame from downstream
    Bridge.relay_from_downstream(bridge_pid, Frame.text("hello echo"))

    # Should receive the echoed frame back from upstream via bridge
    assert_receive {:bridge_frame, {:text, "hello echo"}}, 2_000

    Bridge.downstream_closed(bridge_pid, 1000, "done")
    Process.sleep(100)
  end

  test "relays binary frame from downstream to upstream and gets echo back", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    Bridge.relay_from_downstream(bridge_pid, Frame.binary(<<1, 2, 3, 4>>))

    assert_receive {:bridge_frame, {:binary, <<1, 2, 3, 4>>}}, 2_000

    Bridge.downstream_closed(bridge_pid, 1000, "done")
    Process.sleep(100)
  end

  test "downstream close is propagated to upstream", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    # Close from downstream
    Bridge.downstream_closed(bridge_pid, 1000, "bye")

    # Bridge should stop
    assert_receive {:EXIT, ^bridge_pid, :normal}, 6_000
  end

  test "handler death causes bridge to terminate", %{upstream: upstream} do
    # Spawn a temporary process to act as the "downstream handler"
    handler_pid = spawn(fn -> Process.sleep(:infinity) end)
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(handler_pid, upstream)
    ref = Process.monitor(bridge_pid)
    Process.sleep(200)

    # Kill the handler process - bridge is linked to it
    Process.exit(handler_pid, :kill)

    # Bridge should die (either from the link or from the monitor callback)
    assert_receive {:DOWN, ^ref, :process, ^bridge_pid, _reason}, 2_000
  end

  test "close frame from downstream triggers close handshake", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    # Send a close frame from downstream
    Bridge.relay_from_downstream(bridge_pid, Frame.close(1000, "goodbye"))

    # Bridge should eventually stop after close handshake
    assert_receive {:EXIT, ^bridge_pid, :normal}, 6_000
  end
end
