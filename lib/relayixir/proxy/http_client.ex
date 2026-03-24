defmodule Relayixir.Proxy.HttpClient do
  @moduledoc """
  Mint-based outbound HTTP client for upstream connections.
  """

  require Logger

  @doc """
  Opens a Mint HTTP connection to the upstream.
  """
  def connect(%Relayixir.Proxy.Upstream{} = upstream) do
    scheme = upstream.scheme || :http
    transport_opts = [timeout: upstream.connect_timeout]

    Mint.HTTP.connect(scheme, upstream.host, upstream.port, transport_opts: transport_opts)
  end

  @doc """
  Sends an HTTP request on the Mint connection.
  """
  def send_request(conn, method, path, headers, body \\ nil) do
    Mint.HTTP.request(conn, method, path, headers, body)
  end

  @doc """
  Receives the full response from Mint by looping on messages.

  Returns `{:ok, conn, parts}` where parts is a list of
  `{:status, status}`, `{:headers, headers}`, `{:data, chunk}`, and `:done`.

  Returns `{:error, reason}` on timeout or transport error.
  """
  def recv_response(conn, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    recv_loop(conn, deadline, [])
  end

  @doc """
  Closes the Mint connection.
  """
  def close(conn) do
    Mint.HTTP.close(conn)
  end

  defp recv_loop(conn, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Mint.HTTP.close(conn)
      {:error, :upstream_timeout}
    else
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            :unknown ->
              recv_loop(conn, deadline, acc)

            {:ok, conn, responses} ->
              {new_acc, done?} = process_responses(responses, acc)

              if done? do
                {:ok, conn, Enum.reverse(new_acc)}
              else
                recv_loop(conn, deadline, new_acc)
              end

            {:error, conn, reason, _responses} ->
              Mint.HTTP.close(conn)
              Logger.error("Mint stream error: #{inspect(reason)}")
              {:error, :upstream_invalid_response}
          end
      after
        remaining ->
          Mint.HTTP.close(conn)
          {:error, :upstream_timeout}
      end
    end
  end

  defp process_responses(responses, acc) do
    Enum.reduce(responses, {acc, false}, fn
      {:status, _ref, status}, {parts, _done} ->
        {[{:status, status} | parts], false}

      {:headers, _ref, headers}, {parts, _done} ->
        {[{:headers, headers} | parts], false}

      {:data, _ref, data}, {parts, _done} ->
        {[{:data, data} | parts], false}

      {:done, _ref}, {parts, _done} ->
        {[:done | parts], true}

      {:error, _ref, reason}, {parts, _done} ->
        {[{:error, reason} | parts], true}
    end)
  end
end
