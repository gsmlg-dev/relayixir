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
    ref = Process.monitor(bridge_pid)
    Process.sleep(200)

    # Close from downstream
    Bridge.downstream_closed(bridge_pid, 1000, "bye")

    # Bridge should stop
    assert_receive {:DOWN, ^ref, :process, ^bridge_pid, :normal}, 6_000
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
    ref = Process.monitor(bridge_pid)
    Process.sleep(200)

    # Send a close frame from downstream
    Bridge.relay_from_downstream(bridge_pid, Frame.close(1000, "goodbye"))

    # Bridge should eventually stop after close handshake
    assert_receive {:DOWN, ^ref, :process, ^bridge_pid, :normal}, 6_000
  end

  test "upstream connect failure sends 1014 close frame" do
    Process.flag(:trap_exit, true)

    # Point to a port with nothing listening
    bad_upstream = %Upstream{
      scheme: :http,
      host: "127.0.0.1",
      port: 1,
      path_prefix_rewrite: "/ws",
      connect_timeout: 1_000,
      request_timeout: 60_000,
      websocket?: true,
      host_forward_mode: :preserve,
      metadata: %{}
    }

    {:ok, bridge_pid} = Bridge.start(self(), bad_upstream)
    ref = Process.monitor(bridge_pid)

    # Bridge should send 1014 close frame and terminate
    assert_receive {:bridge_frame, {:close, 1014, "Bad Gateway"}}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^bridge_pid, :normal}, 5_000
  end

  test "frames dropped during connecting state", %{upstream: upstream} do
    Process.flag(:trap_exit, true)

    {:ok, bridge_pid} = Bridge.start(self(), upstream)

    # Immediately send frame before upstream connects
    Bridge.relay_from_downstream(bridge_pid, Frame.text("too early"))

    # Give time to connect
    Process.sleep(200)

    # Bridge should still be alive (frame was dropped, not crashed)
    assert Process.alive?(bridge_pid)

    Bridge.downstream_closed(bridge_pid, 1000, "done")
    Process.sleep(100)
  end

  test "telemetry events emitted for session lifecycle", %{upstream: upstream} do
    Process.flag(:trap_exit, true)
    test_pid = self()

    :telemetry.attach(
      "test-ws-start-#{inspect(test_pid)}",
      [:relayixir, :websocket, :session, :start],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    :telemetry.attach(
      "test-ws-stop-#{inspect(test_pid)}",
      [:relayixir, :websocket, :session, :stop],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    assert_receive {:telemetry, [:relayixir, :websocket, :session, :start], _, %{session_id: _}},
                   2_000

    Bridge.downstream_closed(bridge_pid, 1000, "telemetry test")
    Process.sleep(200)

    assert_receive {:telemetry, [:relayixir, :websocket, :session, :stop], %{duration: _},
                    %{session_id: _, close_code: _}},
                   2_000

    :telemetry.detach("test-ws-start-#{inspect(test_pid)}")
    :telemetry.detach("test-ws-stop-#{inspect(test_pid)}")
  end

  test "frame telemetry emitted for relayed frames", %{upstream: upstream} do
    Process.flag(:trap_exit, true)
    test_pid = self()

    :telemetry.attach(
      "test-ws-frame-out-#{inspect(test_pid)}",
      [:relayixir, :websocket, :frame, :out],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    :telemetry.attach(
      "test-ws-frame-in-#{inspect(test_pid)}",
      [:relayixir, :websocket, :frame, :in],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    {:ok, bridge_pid} = Bridge.start(self(), upstream)
    Process.sleep(200)

    Bridge.relay_from_downstream(bridge_pid, Frame.text("telemetry frame"))

    assert_receive {:telemetry, [:relayixir, :websocket, :frame, :out], _, %{type: :text}}, 2_000
    assert_receive {:telemetry, [:relayixir, :websocket, :frame, :in], _, %{type: :text}}, 2_000

    Bridge.downstream_closed(bridge_pid, 1000, "done")
    Process.sleep(100)

    :telemetry.detach("test-ws-frame-out-#{inspect(test_pid)}")
    :telemetry.detach("test-ws-frame-in-#{inspect(test_pid)}")
  end

  test "exception telemetry emitted on upstream connect failure" do
    Process.flag(:trap_exit, true)
    test_pid = self()

    :telemetry.attach(
      "test-ws-exception-#{inspect(test_pid)}",
      [:relayixir, :websocket, :exception],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    bad_upstream = %Upstream{
      scheme: :http,
      host: "127.0.0.1",
      port: 1,
      path_prefix_rewrite: "/ws",
      connect_timeout: 1_000,
      request_timeout: 60_000,
      websocket?: true,
      host_forward_mode: :preserve,
      metadata: %{}
    }

    {:ok, _bridge_pid} = Bridge.start(self(), bad_upstream)

    assert_receive {:telemetry, [:relayixir, :websocket, :exception], _,
                    %{session_id: _, reason: {:upstream_connect_failed, _}}},
                   5_000

    :telemetry.detach("test-ws-exception-#{inspect(test_pid)}")
  end
end
