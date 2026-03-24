defmodule Relayixir.Proxy.WebSocket.Close do
  @moduledoc """
  Close code/reason mapping and shutdown behavior for WebSocket proxy sessions.
  """

  @normal_codes [1000, 1001]
  @default_close_timeout 5_000

  def normal_close_code?(code) when code in @normal_codes, do: true
  def normal_close_code?(_), do: false

  def close_timeout, do: @default_close_timeout

  @doc """
  Returns the appropriate close code for upstream connection failure after HTTP 101.
  """
  def upstream_failure_code, do: 1014

  @doc """
  Returns the appropriate close code for an internal proxy error.
  """
  def internal_error_code, do: 1011

  @doc """
  Returns a close frame for upstream connect failure (post-upgrade).
  """
  def upstream_connect_failed_frame do
    Relayixir.Proxy.WebSocket.Frame.close(1014, "Bad Gateway")
  end

  @doc """
  Returns a close frame for internal error.
  """
  def internal_error_frame do
    Relayixir.Proxy.WebSocket.Frame.close(1011, "Internal Error")
  end

  @doc """
  Returns a normal close frame.
  """
  def normal_close_frame do
    Relayixir.Proxy.WebSocket.Frame.close(1000, "")
  end

  @doc """
  Determines shutdown behavior based on close initiator and state.
  Returns {:propagate, frame} to forward close to the other side,
  or :terminate to end immediately.
  """
  def shutdown_action(:downstream_close, code, reason) do
    {:propagate_to_upstream, Relayixir.Proxy.WebSocket.Frame.close(code, reason)}
  end

  def shutdown_action(:upstream_close, code, reason) do
    {:propagate_to_downstream, Relayixir.Proxy.WebSocket.Frame.close(code, reason)}
  end

  def shutdown_action(:upstream_failure, _code, _reason) do
    {:propagate_to_downstream, upstream_connect_failed_frame()}
  end

  def shutdown_action(:handler_death, _code, _reason) do
    :terminate
  end
end
