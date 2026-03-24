defmodule Relayixir.Proxy.HttpPlug do
  @moduledoc """
  Orchestrates HTTP reverse proxying: upstream resolution, header preparation,
  request forwarding, and response streaming.
  """

  require Logger

  alias Relayixir.Proxy.{Headers, HttpClient, ErrorMapper, Upstream}

  @doc """
  Proxies the HTTP request to the resolved upstream.
  """
  def call(%Plug.Conn{} = conn, %Upstream{} = upstream) do
    start_time = System.monotonic_time()

    metadata = %{
      method: conn.method,
      path: conn.request_path,
      upstream: "#{upstream.host}:#{upstream.port}"
    }

    :telemetry.execute(
      [:relayixir, :http, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    case do_proxy(conn, upstream) do
      {:ok, conn} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:relayixir, :http, :request, :stop],
          %{duration: duration},
          Map.put(metadata, :status, conn.status)
        )

        conn

      {:error, reason, conn} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:relayixir, :http, :request, :exception],
          %{duration: duration},
          Map.merge(metadata, %{reason: reason})
        )

        if conn.state == :sent do
          conn
        else
          ErrorMapper.send_error(conn, reason)
        end
    end
  end

  defp do_proxy(conn, upstream) do
    with {:ok, body, conn} <- read_body(conn),
         request_headers <- Headers.prepare_request_headers(conn, upstream),
         path <- build_upstream_path(conn, upstream),
         {:ok, mint_conn} <- connect_upstream(upstream),
         method <- String.upcase(conn.method),
         {:ok, mint_conn, _ref} <-
           HttpClient.send_request(mint_conn, method, path, request_headers, body) do
      stream_response(conn, mint_conn, upstream)
    else
      {:error, reason} ->
        {:error, map_error(reason), conn}

      {:error, reason, conn} ->
        {:error, reason, conn}
    end
  end

  defp read_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, conn} -> {:error, :request_body_too_large, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  defp connect_upstream(upstream) do
    :telemetry.execute(
      [:relayixir, :http, :upstream, :connect, :start],
      %{system_time: System.system_time()},
      %{upstream: "#{upstream.host}:#{upstream.port}"}
    )

    case HttpClient.connect(upstream) do
      {:ok, mint_conn} ->
        :telemetry.execute(
          [:relayixir, :http, :upstream, :connect, :stop],
          %{system_time: System.system_time()},
          %{upstream: "#{upstream.host}:#{upstream.port}", result: :ok}
        )

        {:ok, mint_conn}

      {:error, reason} ->
        :telemetry.execute(
          [:relayixir, :http, :upstream, :connect, :stop],
          %{system_time: System.system_time()},
          %{upstream: "#{upstream.host}:#{upstream.port}", result: :error, reason: reason}
        )

        {:error, :upstream_connect_failed}
    end
  end

  defp build_upstream_path(conn, upstream) do
    path =
      case upstream.path_prefix_rewrite do
        nil -> conn.request_path
        rewrite -> rewrite <> conn.request_path
      end

    case conn.query_string do
      "" -> path
      qs -> "#{path}?#{qs}"
    end
  end

  defp stream_response(conn, mint_conn, upstream) do
    case HttpClient.recv_response(mint_conn, upstream.request_timeout) do
      {:ok, mint_conn, parts} ->
        HttpClient.close(mint_conn)
        send_downstream(conn, parts)

      {:error, reason} ->
        {:error, map_error(reason), conn}
    end
  end

  defp send_downstream(conn, parts) do
    {status, headers, data_chunks_reversed} = extract_response_parts(parts)
    data_chunks = Enum.reverse(data_chunks_reversed)

    response_headers = Headers.prepare_response_headers(headers)

    cond do
      status in [204, 304] ->
        conn =
          conn
          |> put_response_headers(response_headers)
          |> Plug.Conn.send_resp(status, "")

        {:ok, conn}

      has_content_length?(response_headers) ->
        body = IO.iodata_to_binary(data_chunks)

        conn =
          conn
          |> put_response_headers(response_headers)
          |> Plug.Conn.send_resp(status, body)

        {:ok, conn}

      true ->
        send_chunked_response(conn, status, response_headers, data_chunks)
    end
  end

  defp extract_response_parts(parts) do
    Enum.reduce(parts, {nil, [], []}, fn
      {:status, status}, {_s, h, d} -> {status, h, d}
      {:headers, headers}, {s, _h, d} -> {s, headers, d}
      {:data, chunk}, {s, h, d} -> {s, h, [chunk | d]}
      :done, acc -> acc
      {:error, _reason}, acc -> acc
    end)
  end

  defp has_content_length?(headers) do
    Enum.any?(headers, fn {name, _} -> String.downcase(name) == "content-length" end)
  end

  defp send_chunked_response(conn, status, headers, data_chunks) do
    conn =
      conn
      |> put_response_headers(headers)
      |> Plug.Conn.send_chunked(status)

    send_chunks(conn, data_chunks)
  end

  defp send_chunks(conn, []) do
    {:ok, conn}
  end

  defp send_chunks(conn, [chunk | rest]) do
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} ->
        send_chunks(conn, rest)

      {:error, :closed} ->
        :telemetry.execute(
          [:relayixir, :http, :downstream, :disconnect],
          %{system_time: System.system_time()},
          %{}
        )

        Logger.info("Downstream client disconnected during chunked response")
        {:ok, conn}
    end
  end

  defp put_response_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {name, value}, conn ->
      Plug.Conn.put_resp_header(conn, String.downcase(name), value)
    end)
  end

  defp map_error(:upstream_timeout), do: :upstream_timeout
  defp map_error(:upstream_connect_failed), do: :upstream_connect_failed
  defp map_error(:upstream_invalid_response), do: :upstream_invalid_response
  defp map_error(:nxdomain), do: :upstream_connect_failed
  defp map_error(:econnrefused), do: :upstream_connect_failed
  defp map_error(%Mint.TransportError{}), do: :upstream_connect_failed
  defp map_error(_), do: :internal_error
end
