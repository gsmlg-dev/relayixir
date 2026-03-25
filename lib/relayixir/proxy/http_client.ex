defmodule Relayixir.Proxy.HttpClient do
  @moduledoc """
  Mint-based outbound HTTP client for upstream connections.
  """

  require Logger

  @doc """
  Opens a Mint HTTP connection to the upstream.
  """
  @spec connect(Relayixir.Proxy.Upstream.t()) :: {:ok, Mint.HTTP.t()} | {:error, term()}
  def connect(%Relayixir.Proxy.Upstream{} = upstream) do
    scheme = upstream.scheme || :http
    transport_opts = [timeout: upstream.connect_timeout]

    Mint.HTTP.connect(scheme, upstream.host, upstream.port, transport_opts: transport_opts)
  end

  @doc """
  Sends an HTTP request on the Mint connection.
  """
  @spec send_request(
          Mint.HTTP.t(),
          String.t(),
          String.t(),
          [{String.t(), String.t()}],
          binary() | nil | :stream
        ) ::
          {:ok, Mint.HTTP.t(), Mint.Types.request_ref()} | {:error, Mint.HTTP.t(), term()}
  def send_request(conn, method, path, headers, body \\ nil) do
    Mint.HTTP.request(conn, method, path, headers, body)
  end

  @doc """
  Receives the full response from Mint by looping on messages.

  Returns `{:ok, conn, parts}` where parts is a list of
  `{:status, status}`, `{:headers, headers}`, `{:data, chunk}`, and `:done`.

  Returns `{:error, reason}` on timeout or transport error.
  """
  @spec recv_response(Mint.HTTP.t(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, Mint.HTTP.t(), list()} | {:error, term()}
  def recv_response(conn, timeout, first_byte_timeout \\ nil) do
    deadline = System.monotonic_time(:millisecond) + timeout

    first_byte_deadline =
      if first_byte_timeout,
        do: System.monotonic_time(:millisecond) + first_byte_timeout,
        else: nil

    recv_loop(conn, deadline, first_byte_deadline, [])
  end

  @doc """
  Streams one chunk (or `:eof`) of a request body on an open streaming request.

  Call after `send_request/5` with `body: :stream`.
  Returns `{:ok, conn}` or `{:error, conn, reason}`.
  """
  @spec stream_body_chunk(Mint.HTTP.t(), Mint.Types.request_ref(), binary() | :eof) ::
          {:ok, Mint.HTTP.t()} | {:error, Mint.HTTP.t(), term()}
  def stream_body_chunk(conn, request_ref, chunk) do
    Mint.HTTP.stream_request_body(conn, request_ref, chunk)
  end

  @doc """
  Closes the Mint connection.
  """
  @spec close(Mint.HTTP.t()) :: {:ok, Mint.HTTP.t()}
  def close(conn) do
    Mint.HTTP.close(conn)
  end

  defp recv_loop(conn, deadline, first_byte_deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    first_byte_remaining =
      if first_byte_deadline && acc == [] do
        first_byte_deadline - System.monotonic_time(:millisecond)
      else
        nil
      end

    effective_remaining =
      case first_byte_remaining do
        nil -> remaining
        fbr -> min(remaining, fbr)
      end

    if effective_remaining <= 0 do
      Mint.HTTP.close(conn)
      {:error, :upstream_timeout}
    else
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            :unknown ->
              recv_loop(conn, deadline, first_byte_deadline, acc)

            {:ok, conn, responses} ->
              {new_acc, done?} = process_responses(responses, acc)

              if done? do
                {:ok, conn, Enum.reverse(new_acc)}
              else
                recv_loop(conn, deadline, first_byte_deadline, new_acc)
              end

            {:error, conn, reason, _responses} ->
              Mint.HTTP.close(conn)
              Logger.error("Mint stream error: #{inspect(reason)}")
              {:error, :upstream_invalid_response}
          end
      after
        effective_remaining ->
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
