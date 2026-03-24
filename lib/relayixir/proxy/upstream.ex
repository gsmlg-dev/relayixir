defmodule Relayixir.Proxy.Upstream do
  @moduledoc """
  Upstream descriptor and route resolution.
  """

  defstruct [
    :scheme,
    :host,
    :port,
    :path_prefix_rewrite,
    request_timeout: 60_000,
    connect_timeout: 5_000,
    first_byte_timeout: 30_000,
    websocket?: false,
    host_forward_mode: :preserve,
    metadata: %{}
  ]

  alias Relayixir.Config.{RouteConfig, UpstreamConfig}

  @doc """
  Resolves the upstream for a given `Plug.Conn` based on configured routes and upstreams.
  """
  def resolve(%Plug.Conn{} = conn) do
    host = conn.host
    path = conn.request_path

    case RouteConfig.find_route(host, path) do
      nil ->
        {:error, :route_not_found}

      route ->
        case UpstreamConfig.get_upstream(route.upstream_name) do
          nil ->
            {:error, :route_not_found}

          upstream_config ->
            upstream = build_upstream(upstream_config, route)
            {:ok, upstream}
        end
    end
  end

  defp build_upstream(config, route) do
    %__MODULE__{
      scheme: Map.get(config, :scheme, :http),
      host: Map.fetch!(config, :host),
      port: Map.get(config, :port, 80),
      path_prefix_rewrite: Map.get(config, :path_prefix_rewrite),
      request_timeout: get_timeout(route, config, :request_timeout, 60_000),
      connect_timeout: get_timeout(route, config, :connect_timeout, 5_000),
      first_byte_timeout: get_timeout(route, config, :first_byte_timeout, 30_000),
      websocket?: Map.get(route, :websocket, false),
      host_forward_mode: Map.get(route, :host_forward_mode, :preserve),
      metadata: Map.get(config, :metadata, %{})
    }
  end

  defp get_timeout(route, config, key, default) do
    route_timeouts = Map.get(route, :timeouts, %{})
    Map.get(route_timeouts, key) || Map.get(config, key) || default
  end
end
