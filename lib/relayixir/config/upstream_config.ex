defmodule Relayixir.Config.UpstreamConfig do
  @moduledoc """
  Agent-based upstream configuration store. Upstreams are keyed by name.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Returns the upstream config for the given name.
  """
  def get_upstream(name) do
    Agent.get(__MODULE__, &Map.get(&1, name))
  end

  @doc """
  Replaces all upstreams with the given map of name => config.
  """
  def put_upstreams(upstreams) when is_map(upstreams) do
    Agent.update(__MODULE__, fn _ -> upstreams end)
  end

  @doc """
  Returns all configured upstreams as a map.
  """
  def list_upstreams do
    Agent.get(__MODULE__, & &1)
  end
end
