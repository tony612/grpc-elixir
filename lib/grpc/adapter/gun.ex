defmodule GRPC.Adapter.Gun do
  @moduledoc false

  # A client adapter using Gun.
  # conn_pid and stream_ref is stored in `GRPC.Server.Stream`.

  @default_transport_opts [nodelay: true]

  @spec connect(GRPC.Channel.t(), any) :: {:ok, GRPC.Channel.t()} | {:error, any}
  def connect(channel, nil), do: connect(channel, %{})
  def connect(%{scheme: "https"} = channel, opts), do: connect_securely(channel, opts)
  def connect(channel, opts), do: connect_insecurely(channel, opts)

  defp connect_securely(%{cred: %{ssl: ssl}} = channel, opts) do
    transport_opts = Map.get(opts, :transport_opts, @default_transport_opts ++ ssl)
    open_opts = %{transport: :ssl, protocols: [:http2], transport_opts: transport_opts}
    open_opts = Map.merge(opts, open_opts)

    do_connect(channel, open_opts)
  end

  defp connect_insecurely(channel, opts) do
    transport_opts = Map.get(opts, :transport_opts, @default_transport_opts)
    open_opts = %{transport: :tcp, protocols: [:http2], transport_opts: transport_opts}
    open_opts = Map.merge(opts, open_opts)

    do_connect(channel, open_opts)
  end

  defp do_connect(%{host: host, port: port} = channel, open_opts) do
    {:ok, conn_pid} = open(host, port, open_opts)

    case :gun.await_up(conn_pid) do
      {:ok, :http2} ->
        {:ok, Map.put(channel, :adapter_payload, %{conn_pid: conn_pid})}

      {:ok, proto} ->
        {:error, "Error when opening connection: protocol #{proto} is not http2"}

      {:error, reason} ->
        {:error, "Error when opening connection: #{inspect(reason)}"}
    end
  end

  def disconnect(%{adapter_payload: %{conn_pid: gun_pid}} = channel)
      when is_pid(gun_pid) do
    :ok = :gun.close(gun_pid)
    {:ok, %{channel | adapter_payload: %{conn_pid: nil}}}
  end

  defp open({:local, socket_path}, _port, open_opts),
    do: :gun.open_unix(socket_path, open_opts)

  defp open(host, port, open_opts),
    do: :gun.open(String.to_charlist(host), port, open_opts)

  @spec send_request(GRPC.Client.Stream.t(), binary, map) :: GRPC.Client.Stream.t()
  def send_request(stream, message, opts) do
    stream_ref = do_send_request(stream, message, opts)
    GRPC.Client.Stream.put_payload(stream, :stream_ref, stream_ref)
  end

  defp do_send_request(
         %{channel: %{adapter_payload: %{conn_pid: conn_pid}}, path: path} = stream,
         message,
         opts
       ) do
    headers = GRPC.Transport.HTTP2.client_headers_without_reserved(stream, opts)
    {:ok, data, _} = GRPC.Message.to_data(message, opts)
    :gun.post(conn_pid, path, headers, data)
  end

  def send_headers(
        %{channel: %{adapter_payload: %{conn_pid: conn_pid}}, path: path} = stream,
        opts
      ) do
    headers = GRPC.Transport.HTTP2.client_headers_without_reserved(stream, opts)
    stream_ref = :gun.post(conn_pid, path, headers)
    GRPC.Client.Stream.put_payload(stream, :stream_ref, stream_ref)
  end

  def send_data(%{channel: channel, payload: %{stream_ref: stream_ref}} = stream, message, opts) do
    conn_pid = channel.adapter_payload[:conn_pid]
    fin = if opts[:send_end_stream], do: :fin, else: :nofin
    {:ok, data, _} = GRPC.Message.to_data(message, opts)
    :gun.data(conn_pid, stream_ref, fin, data)
    stream
  end

  def end_stream(%{channel: channel, payload: %{stream_ref: stream_ref}} = stream) do
    conn_pid = channel.adapter_payload[:conn_pid]
    :gun.data(conn_pid, stream_ref, :fin, "")
    stream
  end

  def cancel(%{conn_pid: conn_pid}, %{stream_ref: stream_ref}) do
    :gun.cancel(conn_pid, stream_ref)
  end

  def recv_headers(%{conn_pid: conn_pid}, %{stream_ref: stream_ref}, opts) do
    case await(conn_pid, stream_ref, opts[:timeout]) do
      {:response, headers, fin} ->
        {:ok, headers, fin}

      error = {:error, _} ->
        error

      other ->
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.unknown(),
           "unexpected when waiting for headers: #{inspect(other)}"
         )}
    end
  end

  def recv_data_or_trailers(%{conn_pid: conn_pid}, %{stream_ref: stream_ref}, opts) do
    case await(conn_pid, stream_ref, opts[:timeout]) do
      data = {:data, _} ->
        data

      trailers = {:trailers, _} ->
        trailers

      error = {:error, _} ->
        error

      other ->
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.unknown(),
           "unexpected when waiting for data: #{inspect(other)}"
         )}
    end
  end

  defp await(conn_pid, stream_ref, timeout) do
    # We should use server timeout for most time
    timeout =
      if is_integer(timeout) do
        timeout * 2
      else
        timeout
      end

    case :gun.await(conn_pid, stream_ref, timeout) do
      {:response, :fin, status, headers} ->
        if status == 200 do
          headers = Enum.into(headers, %{})

          case headers["grpc-status"] do
            nil ->
              {:error,
               GRPC.RPCError.exception(
                 GRPC.Status.internal(),
                 "shouldn't finish when getting headers"
               )}

            "0" ->
              {:response, headers, :fin}

            _ ->
              {:error,
               GRPC.RPCError.exception(
                 String.to_integer(headers["grpc-status"]),
                 headers["grpc-message"]
               )}
          end
        else
          {:error,
           GRPC.RPCError.exception(
             GRPC.Status.internal(),
             "status got is #{status} instead of 200"
           )}
        end

      {:response, :nofin, status, headers} ->
        if status == 200 do
          headers = Enum.into(headers, %{})

          if headers["grpc-status"] && headers["grpc-status"] != "0" do
            {:error,
             GRPC.RPCError.exception(
               String.to_integer(headers["grpc-status"]),
               headers["grpc-message"]
             )}
          else
            {:response, headers, :nofin}
          end
        else
          {:error,
           GRPC.RPCError.exception(
             GRPC.Status.internal(),
             "status got is #{status} instead of 200"
           )}
        end

      {:data, :fin, _} ->
        {:error,
         GRPC.RPCError.exception(GRPC.Status.internal(), "shouldn't finish when getting data")}

      {:data, :nofin, data} ->
        {:data, data}

      trailers = {:trailers, _} ->
        trailers

      {:error, :timeout} ->
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.deadline_exceeded(),
           "timeout when waiting for server"
         )}

      {:error, {reason, msg}} ->
        {:error,
         GRPC.RPCError.exception(GRPC.Status.unknown(), "#{inspect(reason)}: #{inspect(msg)}")}

      {:error, reason} ->
        {:error, GRPC.RPCError.exception(GRPC.Status.unknown(), "#{inspect(reason)}")}

      other ->
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.unknown(),
           "unexpected message when waiting: #{inspect(other)}"
         )}
    end
  end
end
