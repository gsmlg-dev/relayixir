defmodule Relayixir.Proxy.WebSocket.PlugTest do
  use ExUnit.Case

  alias Relayixir.Proxy.WebSocket.Plug, as: WsPlug
  alias Relayixir.Proxy.Upstream

  describe "valid_websocket_upgrade? validation" do
    test "rejects request missing upgrade header" do
      conn =
        Plug.Test.conn(:get, "/ws")
        |> Plug.Conn.put_req_header("connection", "Upgrade")
        |> Plug.Conn.put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
        |> Plug.Conn.put_req_header("sec-websocket-version", "13")

      upstream = %Upstream{
        scheme: :http,
        host: "127.0.0.1",
        port: 9999,
        websocket?: true,
        host_forward_mode: :preserve,
        metadata: %{}
      }

      result = WsPlug.call(conn, upstream)
      assert result.status == 400
      assert result.resp_body == "Invalid WebSocket upgrade request"
    end

    test "rejects request missing connection header" do
      conn =
        Plug.Test.conn(:get, "/ws")
        |> Plug.Conn.put_req_header("upgrade", "websocket")
        |> Plug.Conn.put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
        |> Plug.Conn.put_req_header("sec-websocket-version", "13")

      upstream = %Upstream{
        scheme: :http,
        host: "127.0.0.1",
        port: 9999,
        websocket?: true,
        host_forward_mode: :preserve,
        metadata: %{}
      }

      result = WsPlug.call(conn, upstream)
      assert result.status == 400
    end

    test "rejects request missing sec-websocket-key" do
      conn =
        Plug.Test.conn(:get, "/ws")
        |> Plug.Conn.put_req_header("upgrade", "websocket")
        |> Plug.Conn.put_req_header("connection", "Upgrade")
        |> Plug.Conn.put_req_header("sec-websocket-version", "13")

      upstream = %Upstream{
        scheme: :http,
        host: "127.0.0.1",
        port: 9999,
        websocket?: true,
        host_forward_mode: :preserve,
        metadata: %{}
      }

      result = WsPlug.call(conn, upstream)
      assert result.status == 400
    end

    test "rejects request with wrong sec-websocket-version" do
      conn =
        Plug.Test.conn(:get, "/ws")
        |> Plug.Conn.put_req_header("upgrade", "websocket")
        |> Plug.Conn.put_req_header("connection", "Upgrade")
        |> Plug.Conn.put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
        |> Plug.Conn.put_req_header("sec-websocket-version", "8")

      upstream = %Upstream{
        scheme: :http,
        host: "127.0.0.1",
        port: 9999,
        websocket?: true,
        host_forward_mode: :preserve,
        metadata: %{}
      }

      result = WsPlug.call(conn, upstream)
      assert result.status == 400
    end
  end
end
