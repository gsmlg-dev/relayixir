defmodule Relayixir.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:relayixir, :port, 4000)

    children = [
      Relayixir.Config.RouteConfig,
      Relayixir.Config.UpstreamConfig,
      Relayixir.Telemetry.Events,
      {DynamicSupervisor,
       name: Relayixir.Proxy.WebSocket.BridgeSupervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: Relayixir.Proxy.WebSocket.BridgeRegistry},
      {Bandit, plug: Relayixir.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: Relayixir.Supervisor]

    with {:ok, sup} <- Supervisor.start_link(children, opts) do
      # Auto-load routes and upstreams from application config if present.
      Relayixir.reload()
      {:ok, sup}
    end
  end
end
