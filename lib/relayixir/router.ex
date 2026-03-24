defmodule Relayixir.Router do
  @moduledoc """
  Top-level Plug router. Dispatches requests to the HTTP or WebSocket proxy path.
  """

  use Plug.Router

  alias Relayixir.Proxy.{Upstream, ErrorMapper, HttpPlug}

  plug(Plug.RequestId)
  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  match _ do
    case Upstream.resolve(conn) do
      {:ok, %Upstream{websocket?: true} = upstream} ->
        if websocket_upgrade?(conn) do
          Relayixir.Proxy.WebSocket.Plug.call(conn, upstream)
        else
          HttpPlug.call(conn, upstream)
        end

      {:ok, upstream} ->
        HttpPlug.call(conn, upstream)

      {:error, :route_not_found} ->
        ErrorMapper.send_error(conn, :route_not_found)
    end
  end

  defp websocket_upgrade?(conn) do
    upgrade_header =
      conn
      |> Plug.Conn.get_req_header("upgrade")
      |> Enum.map(&String.downcase/1)

    "websocket" in upgrade_header
  end
end
