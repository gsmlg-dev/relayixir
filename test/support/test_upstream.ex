defmodule Relayixir.TestUpstream do
  @moduledoc """
  A simple Plug-based test upstream server for integration testing.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/ok" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end

  get "/chunked" do
    conn =
      conn
      |> put_resp_content_type("text/plain")
      |> send_chunked(200)

    {:ok, conn} = chunk(conn, "chunk1")
    {:ok, conn} = chunk(conn, "chunk2")
    conn
  end

  get "/empty" do
    send_resp(conn, 204, "")
  end

  get "/slow" do
    Process.sleep(2_000)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "slow response")
  end

  post "/echo" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  get "/headers" do
    headers_str =
      conn.req_headers
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("\n")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, headers_str)
  end

  get "/with-content-length" do
    body = "Hello, World!"

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("content-length", Integer.to_string(byte_size(body)))
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
