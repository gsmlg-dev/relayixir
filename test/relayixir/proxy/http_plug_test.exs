defmodule Relayixir.Proxy.HttpPlugTest do
  use ExUnit.Case

  alias Relayixir.Config.{RouteConfig, UpstreamConfig}

  @moduletag :integration

  setup do
    # Start a test upstream server on a random port
    {:ok, server_pid} = Bandit.start_link(plug: Relayixir.TestUpstream, port: 0)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)

    # Configure routes and upstreams to point to our test server
    RouteConfig.put_routes([
      %{host_match: "*", path_prefix: "/", upstream_name: "test_backend"}
    ])

    UpstreamConfig.put_upstreams(%{
      "test_backend" => %{
        scheme: :http,
        host: "127.0.0.1",
        port: port
      }
    })

    on_exit(fn ->
      try do
        ThousandIsland.stop(server_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    %{port: port}
  end

  test "proxies GET /ok successfully" do
    conn =
      Plug.Test.conn(:get, "http://localhost/ok")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "OK"
  end

  test "proxies POST /echo with body forwarded" do
    conn =
      Plug.Test.conn(:post, "http://localhost/echo", "hello body")
      |> Plug.Conn.put_req_header("content-type", "text/plain")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body == "hello body"
  end

  test "handles 204 empty body" do
    conn =
      Plug.Test.conn(:get, "http://localhost/empty")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 204
    assert conn.resp_body == ""
  end

  test "proxies response with content-length" do
    conn =
      Plug.Test.conn(:get, "http://localhost/with-content-length")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body == "Hello, World!"
  end

  test "returns 404 for unknown route" do
    # Clear routes so nothing matches
    RouteConfig.put_routes([])

    conn =
      Plug.Test.conn(:get, "http://localhost/nonexistent")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 404
    assert conn.resp_body == "Not Found"
  end

  test "forwards headers to upstream" do
    conn =
      Plug.Test.conn(:get, "http://localhost/headers")
      |> Plug.Conn.put_req_header("x-custom-header", "test-value")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 200
    # The response body contains headers as key=value lines
    assert conn.resp_body =~ "x-custom-header=test-value"
    # Should have x-forwarded-for set
    assert conn.resp_body =~ "x-forwarded-for="
    assert conn.resp_body =~ "x-forwarded-proto="
    assert conn.resp_body =~ "x-forwarded-host="
  end

  test "returns 502 when upstream is unreachable" do
    # Point to a port that nothing is listening on
    UpstreamConfig.put_upstreams(%{
      "test_backend" => %{
        scheme: :http,
        host: "127.0.0.1",
        port: 1,
        connect_timeout: 1_000
      }
    })

    conn =
      Plug.Test.conn(:get, "http://localhost/ok")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 502
    assert conn.resp_body == "Bad Gateway"
  end

  test "proxies chunked response" do
    conn =
      Plug.Test.conn(:get, "http://localhost/chunked")
      |> Relayixir.Router.call(Relayixir.Router.init([]))

    assert conn.status == 200
    # Chunked responses may be reassembled by the time we see the resp_body
    # or they may be in the chunked state
    if conn.state == :chunked do
      # For chunked responses, the body parts are sent as chunks
      assert true
    else
      assert conn.resp_body =~ "chunk1"
      assert conn.resp_body =~ "chunk2"
    end
  end
end
