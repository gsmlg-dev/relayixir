defmodule Relayixir do
  @moduledoc """
  Elixir-native HTTP/WebSocket reverse proxy built on Bandit + Plug + Mint.
  """

  @doc """
  Configure routes for the proxy.
  """
  defdelegate configure_routes(routes), to: Relayixir.Config.RouteConfig, as: :put_routes

  @doc """
  Configure upstreams for the proxy.
  """
  defdelegate configure_upstreams(upstreams),
    to: Relayixir.Config.UpstreamConfig,
    as: :put_upstreams
end
