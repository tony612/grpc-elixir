defmodule GRPC.Stub do
  @moduledoc """
  A module acting as the interface for gRPC client.

  You can do everything in the client side via `GRPC.Stub`, including connecting,
  sending/receiving steaming or non-steaming requests, canceling calls and so on.

  A service is needed to define a stub:

      defmodule Greeter.Service do
        use GRPC.Service, name: "ping"

        rpc :SayHello, Request, Reply
        rpc :SayGoodbye, stream(Request), stream(Reply)
      end

      defmodule Greeter.Stub do
        use GRPC.Stub, service: Greeter.Service
      end

  so that functions `say_hello/2` and `say_goodbye/1` will be generated for you:

      # Unary call
      {:ok, reply} = Greeter.Stub.say_hello(channel, request)

      # Streaming call
      stream = Greeter.Stub.say_goodbye(channel)
      GRPC.Stub.send_request(stream, request, end_stream: true)
      {:ok, reply_enum} = GRPC.Stub.recv(stream)
      replies = Enum.map(reply_enum, fn({:ok, reply}) -> reply end)

  Note that streaming calls are very different with unary calls. If request is
  streaming, the RPC function only accepts channel as argument and returns a
  `GRPC.Client.Stream`. You can send streaming requests one by one via `send_request/3`,
  then use `recv/1` to receive the reply. And if the reply is streaming, `recv/1`
  returns a `Stream`.

  You can refer to `call/6` for doc of your RPC functions.
  """
  alias GRPC.Channel
  @insecure_scheme "http"
  @secure_scheme "https"
  @canceled_error GRPC.RPCError.exception(GRPC.Status.cancelled(), "The operation was cancelled")
  # 10 seconds
  @default_timeout 10000

  @type rpc_return ::
          {:ok, struct}
          | {:ok, struct, map}
          | GRPC.Client.Stream.t()
          | {:ok, Enumerable.t()}
          | {:ok, Enumerable.t(), map}
          | {:error, GRPC.RPCError.t()}

  require Logger

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      service_mod = opts[:service]
      service_name = service_mod.__meta__(:name)

      Enum.each(service_mod.__rpc_calls__, fn {name, {_, req_stream}, {_, res_stream}} = rpc ->
        func_name = name |> to_string |> Macro.underscore()
        path = "/#{service_name}/#{name}"
        grpc_type = GRPC.Service.grpc_type(rpc)

        stream = %GRPC.Client.Stream{
          service_name: service_name,
          method_name: to_string(name),
          grpc_type: grpc_type,
          path: path,
          rpc: put_elem(rpc, 0, func_name),
          server_stream: res_stream
        }

        if req_stream do
          def unquote(String.to_atom(func_name))(channel, opts \\ []) do
            GRPC.Stub.call(
              unquote(service_mod),
              unquote(Macro.escape(rpc)),
              %{unquote(Macro.escape(stream)) | channel: channel},
              nil,
              opts
            )
          end
        else
          def unquote(String.to_atom(func_name))(channel, request, opts \\ []) do
            GRPC.Stub.call(
              unquote(service_mod),
              unquote(Macro.escape(rpc)),
              %{unquote(Macro.escape(stream)) | channel: channel},
              request,
              opts
            )
          end
        end
      end)
    end
  end

  @type channel :: GRPC.ClientAdapter.channel()

  @doc """
  Establish a connection with gRPC server and return `GRPC.Channel` needed for
  sending requests.

  ## Examples

      iex> GRPC.Stub.connect("localhost:50051")
      {:ok, channel}

      iex> GRPC.Stub.connect("localhost:50051", accepted_compressors: [GRPC.Compressor.Gzip])
      {:ok, channel}

      iex> GRPC.Stub.connect("/paht/to/unix.sock")
      {:ok, channel}

  ## Options

    * `:cred` - a `GRPC.Credential` used to indicate it's a secure connection.
      An insecure connection will be created without this option.
    * `:adapter` - custom client adapter
    * `:interceptors` - client interceptors
    * `:codec` - client will use this to encode and decode binary message
    * `:compressor` - the client will use this to compress requests and decompress responses. If this is set, accepted_compressors
        will be appended also, so this can be used safely without `:accesspted_compressors`.
    * `:accepted_compressors` - tell servers accepted compressors, this can be used without `:compressor`
    * `:headers` - headers to attach to each request
  """
  @spec connect(String.t(), Keyword.t()) :: {:ok, channel} | {:error, any}
  def connect(addr, opts \\ []) when is_binary(addr) and is_list(opts) do
    {host, port} =
      case String.split(addr, ":") do
        [host, port] -> {host, port}
        [socket_path] -> {{:local, socket_path}, 0}
      end

    connect(host, port, opts)
  end

  @spec connect(String.t(), binary | non_neg_integer, keyword) ::
          {:ok, channel} | {:error, any}
  def connect(host, port, opts) when is_binary(port) do
    connect(host, String.to_integer(port), opts)
  end

  def connect(host, port, opts) when is_integer(port) do
    adapter =
      Keyword.get(
        opts,
        :adapter,
        Application.get_env(:grpc, :http2_client_adapter, GRPC.Adapter.Gun)
      )

    cred = Keyword.get(opts, :cred)
    scheme = if cred, do: @secure_scheme, else: @insecure_scheme
    interceptors = Keyword.get(opts, :interceptors, []) |> init_interceptors
    codec = Keyword.get(opts, :codec, GRPC.Codec.Proto)
    compressor = Keyword.get(opts, :compressor)
    accepted_compressors = Keyword.get(opts, :accepted_compressors) || []
    headers = Keyword.get(opts, :headers) || []

    accepted_compressors =
      if compressor do
        Enum.uniq([compressor | accepted_compressors])
      else
        accepted_compressors
      end

    %Channel{
      host: host,
      port: port,
      scheme: scheme,
      cred: cred,
      adapter: adapter,
      interceptors: interceptors,
      codec: codec,
      compressor: compressor,
      accepted_compressors: accepted_compressors,
      headers: headers
    }
    |> adapter.connect(opts[:adapter_opts])
  end

  def retry_timeout(curr) when curr < 11 do
    timeout =
      if curr < 11 do
        :math.pow(1.6, curr - 1) * 1000
      else
        120_000
      end

    uniform_fn =
      if function_exported?(:rand, :uniform_real, 0) do
        :uniform_real
      else
        :uniform
      end

    jitter = (apply(:rand, uniform_fn, []) - 0.5) / 2.5

    round(timeout + jitter * timeout)
  end

  defp init_interceptors(interceptors) do
    Enum.map(interceptors, fn
      {interceptor, opts} -> {interceptor, interceptor.init(opts)}
      interceptor -> {interceptor, interceptor.init([])}
    end)
  end

  @doc """
  Disconnects the adapter and frees any resources the adapter is consuming
  """
  @spec disconnect(channel) :: {:ok, channel} | {:error, any}
  def disconnect(%Channel{adapter: adapter} = channel) do
    adapter.disconnect(channel)
  end

  @doc """
  The actual function invoked when invoking a rpc function.

  ## Returns

    * Unary calls. `{:ok, reply} | {:ok, headers_map} | {:error, error}`
    * Client streaming. A `GRPC.Client.Stream`
    * Server streaming. `{:ok, Enumerable.t} | {:ok, Enumerable.t, trailers_map} | {:error, error}`

  ## Options

    * `:timeout` - request timeout. Default is 10s for unary calls and `:infinity` for
      client or server streaming calls
    * `:deadline` - when the request is timeout, will override timeout
    * `:metadata` - a map, your custom metadata
    * `:return_headers` - default is false. When it's true, a three elem tuple will be returned
      with the last elem being a map of headers `%{headers: headers, trailers: trailers}`(unary) or
      `%{headers: headers}`(server streaming)
  """
  @spec call(atom, tuple, GRPC.Client.Stream.t(), struct | nil, keyword) :: rpc_return
  def call(_service_mod, rpc, %{channel: channel} = stream, request, opts) do
    {_, {req_mod, req_stream}, {res_mod, response_stream}} = rpc

    stream = %{stream | request_mod: req_mod, response_mod: res_mod}

    opts =
      if req_stream || response_stream do
        parse_req_opts([{:timeout, :infinity} | opts])
      else
        parse_req_opts([{:timeout, @default_timeout} | opts])
      end

    compressor = Map.get(opts, :compressor, channel.compressor)
    accepted_compressors = Map.get(opts, :accepted_compressors, [])

    accepted_compressors =
      if compressor do
        Enum.uniq([compressor | accepted_compressors])
      else
        accepted_compressors
      end

    stream = %{
      stream
      | codec: Map.get(opts, :codec, channel.codec),
        compressor: Map.get(opts, :compressor, channel.compressor),
        accepted_compressors: accepted_compressors
    }

    do_call(req_stream, stream, request, opts)
  end

  defp do_call(
         false,
         %{channel: channel} = stream,
         request,
         opts
       ) do
    last = fn %{codec: codec, compressor: compressor} = s, _ ->
      message = codec.encode(request)
      opts = Map.put(opts, :compressor, compressor)

      s
      |> channel.adapter.send_request(message, opts)
      |> recv(opts)
    end

    next =
      Enum.reduce(channel.interceptors, last, fn {interceptor, opts}, acc ->
        fn s, r -> interceptor.call(s, r, acc, opts) end
      end)

    next.(stream, request)
  end

  defp do_call(true, %{channel: channel} = stream, req, opts) do
    last = fn s, _ ->
      channel.adapter.send_headers(s, opts)
    end

    next =
      Enum.reduce(channel.interceptors, last, fn {interceptor, opts}, acc ->
        fn s, r -> interceptor.call(s, r, acc, opts) end
      end)

    next.(stream, req)
  end

  @doc """
  DEPRECATED. Use `send_request/3` instead
  """
  @deprecated "Use send_request/3 instead"
  def stream_send(stream, request, opts \\ []) do
    send_request(stream, request, opts)
  end

  @doc """
  Send streaming requests.

  The last request can be sent with `:end_stream` option, or you can call `end_stream/1`
  to send a frame with END_STREAM flag to end the stream.

  ## Options

    * `:end_stream` - indicates it's the last one request, then the stream will be in
      half_closed state. Default is false.
  """
  @spec send_request(GRPC.Client.Stream.t(), struct, Keyword.t()) :: GRPC.Client.Stream.t()
  def send_request(%{__interface__: interface} = stream, request, opts \\ []) do
    interface[:send_request].(stream, request, opts)
  end

  @doc """
  Send END_STREAM frame to end the stream.

  The stream will be in half_closed state after this is called.

  ## Examples

      iex> stream = GRPC.Stub.send_request(stream, request)
      iex> GRPC.Stub.end_stream(stream)
  """
  @spec end_stream(GRPC.Client.Stream.t()) :: GRPC.Client.Stream.t()
  def end_stream(%{channel: channel} = stream) do
    channel.adapter.end_stream(stream)
  end

  @doc """
  Cancel a stream in a streaming client.

  After that, callings to `recv/2` will return a CANCEL error.
  """
  def cancel(%{channel: channel, payload: payload} = stream) do
    case channel.adapter.cancel(channel.adapter_payload, payload) do
      :ok -> %{stream | canceled: true}
      other -> other
    end
  end

  @doc """
  Receive replies when requests are streaming.

  * If the reply is not streaming, a normal reply struct will be returned
  * If the reply is streaming, a enumerable `Stream` will be returned.
    You can use `Enum` to fetch further replies or `Stream` to manipulate it.
    Each item in the `Enumerable` is a tuple `{:ok, reply}` or `{:error, error}`.
    When `:return_headers` is true, the last item in the `Enumerable` will be
    `{:trailers, map}`

  ## Examples

      # Reply is not streaming
      {:ok, reply} = GRPC.Stub.recv(stream)

      # Reply is streaming
      {:ok, enum} = GRPC.Stub.recv(stream)
      replies = Enum.map(enum, fn({:ok, reply}) -> reply end)

  ## Options

    * `:timeout` - request timeout
    * `:deadline` - when the request is timeout, will override timeout
    * `:return_headers` - when true, headers will be returned.
  """
  @spec recv(GRPC.Client.Stream.t(), keyword | map) ::
          {:ok, struct}
          | {:ok, struct, map}
          | {:ok, Enumerable.t()}
          | {:ok, Enumerable.t(), map}
          | {:error, any}
  def recv(stream, opts \\ [])

  def recv(%{canceled: true}, _) do
    {:error, @canceled_error}
  end

  def recv(%{__interface__: interface} = stream, opts) do
    opts =
      if is_list(opts) do
        parse_recv_opts(opts)
      else
        opts
      end

    interface[:recv].(stream, opts)
  end

  @doc false
  def do_recv(%{server_stream: true, channel: channel, payload: payload} = stream, opts) do
    case recv_headers(channel.adapter, channel.adapter_payload, payload, opts) do
      {:ok, headers, is_fin} ->
        res_enum =
          case is_fin do
            :fin -> []
            :nofin -> response_stream(stream, opts)
          end

        if opts[:return_headers] do
          {:ok, res_enum, %{headers: headers}}
        else
          {:ok, res_enum}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def do_recv(
        %{payload: payload, channel: channel} = stream,
        opts
      ) do
    with {:ok, headers, _is_fin} <-
           recv_headers(channel.adapter, channel.adapter_payload, payload, opts),
         {:ok, body, trailers} <-
           recv_body(channel.adapter, channel.adapter_payload, payload, opts) do
      {status, msg} = parse_response(stream, headers, body, trailers)

      if opts[:return_headers] do
        {status, msg, %{headers: headers, trailers: trailers}}
      else
        {status, msg}
      end
    else
      error = {:error, _} ->
        error
    end
  end

  defp recv_headers(adapter, conn_payload, stream_payload, opts) do
    case adapter.recv_headers(conn_payload, stream_payload, opts) do
      {:ok, headers, is_fin} ->
        {:ok, GRPC.Transport.HTTP2.decode_headers(headers), is_fin}

      other ->
        other
    end
  end

  defp recv_body(adapter, conn_payload, stream_payload, opts) do
    recv_body(adapter, conn_payload, stream_payload, "", opts)
  end

  defp recv_body(adapter, conn_payload, stream_payload, acc, opts) do
    case adapter.recv_data_or_trailers(conn_payload, stream_payload, opts) do
      {:data, data} ->
        recv_body(adapter, conn_payload, stream_payload, <<acc::binary, data::binary>>, opts)

      {:trailers, trailers} ->
        {:ok, acc, GRPC.Transport.HTTP2.decode_headers(trailers)}
    end
  end

  defp parse_response(
         %{response_mod: res_mod, codec: codec, accepted_compressors: accepted_compressors},
         headers,
         body,
         trailers
       ) do
    case parse_trailers(trailers) do
      :ok ->
        compressor =
          case headers do
            %{"grpc-encoding" => encoding} ->
              Enum.find(accepted_compressors, nil, fn c -> c.name() == encoding end)

            _ ->
              nil
          end

        case GRPC.Message.from_data(%{compressor: compressor}, body) do
          {:ok, msg} ->
            {:ok, codec.decode(msg, res_mod)}

          err ->
            err
        end

      error ->
        error
    end
  end

  defp parse_trailers(trailers) do
    status = String.to_integer(trailers["grpc-status"])

    if status == GRPC.Status.ok() do
      :ok
    else
      {:error, %GRPC.RPCError{status: status, message: trailers["grpc-message"]}}
    end
  end

  defp response_stream(
         %{
           channel: %{adapter: adapter, adapter_payload: ap},
           response_mod: res_mod,
           codec: codec,
           payload: payload
         },
         opts
       ) do
    state = %{
      adapter: adapter,
      adapter_payload: ap,
      payload: payload,
      buffer: <<>>,
      fin: false,
      need_more: true,
      opts: opts,
      response_mod: res_mod,
      codec: codec
    }

    Stream.unfold(state, fn s -> read_stream(s) end)
  end

  defp read_stream(%{buffer: <<>>, fin: true, fin_resp: nil}), do: nil

  defp read_stream(%{buffer: <<>>, fin: true, fin_resp: fin_resp} = s),
    do: {fin_resp, Map.put(s, :fin_resp, nil)}

  defp read_stream(
         %{
           adapter: adapter,
           adapter_payload: ap,
           payload: payload,
           buffer: buffer,
           need_more: true,
           opts: opts
         } = s
       ) do
    case adapter.recv_data_or_trailers(ap, payload, opts) do
      {:data, data} ->
        buffer = buffer <> data
        new_s = s |> Map.put(:need_more, false) |> Map.put(:buffer, buffer)
        read_stream(new_s)

      {:trailers, trailers} ->
        trailers = GRPC.Transport.HTTP2.decode_headers(trailers)

        case parse_trailers(trailers) do
          :ok ->
            fin_resp =
              if opts[:return_headers] do
                {:trailers, trailers}
              end

            new_s = s |> Map.put(:fin, true) |> Map.put(:fin_resp, fin_resp)
            read_stream(new_s)

          error ->
            {error, %{buffer: <<>>, fin: true, fin_resp: nil}}
        end

      error = {:error, _} ->
        {error, %{buffer: <<>>, fin: true, fin_resp: nil}}
    end
  end

  defp read_stream(%{buffer: buffer, need_more: false, response_mod: res_mod, codec: codec} = s) do
    case GRPC.Message.get_message(buffer) do
      # TODO
      {{_, message}, rest} ->
        reply = codec.decode(message, res_mod)
        new_s = Map.put(s, :buffer, rest)
        {{:ok, reply}, new_s}

      _ ->
        read_stream(Map.put(s, :need_more, true))
    end
  end

  defp parse_req_opts(list) when is_list(list) do
    parse_req_opts(list, %{})
  end

  defp parse_req_opts([{:timeout, timeout} | t], acc) do
    parse_req_opts(t, Map.put(acc, :timeout, timeout))
  end

  defp parse_req_opts([{:deadline, deadline} | t], acc) do
    parse_req_opts(t, Map.put(acc, :timeout, GRPC.TimeUtils.to_relative(deadline)))
  end

  defp parse_req_opts([{:compressor, compressor} | t], acc) do
    parse_req_opts(t, Map.put(acc, :compressor, compressor))
  end

  defp parse_req_opts([{:accepted_compressors, compressors} | t], acc) do
    parse_req_opts(t, Map.put(acc, :accepted_compressors, compressors))
  end

  defp parse_req_opts([{:grpc_encoding, grpc_encoding} | t], acc) do
    parse_req_opts(t, Map.put(acc, :grpc_encoding, grpc_encoding))
  end

  defp parse_req_opts([{:metadata, metadata} | t], acc) do
    parse_req_opts(t, Map.put(acc, :metadata, metadata))
  end

  defp parse_req_opts([{:content_type, content_type} | t], acc) do
    Logger.warn(":content_type has been deprecated, please use :codec")
    parse_req_opts(t, Map.put(acc, :content_type, content_type))
  end

  defp parse_req_opts([{:codec, codec} | t], acc) do
    parse_req_opts(t, Map.put(acc, :codec, codec))
  end

  defp parse_req_opts([{:return_headers, return_headers} | t], acc) do
    parse_req_opts(t, Map.put(acc, :return_headers, return_headers))
  end

  defp parse_req_opts([{key, _} | _], _) do
    raise ArgumentError, "option #{inspect(key)} is not supported"
  end

  defp parse_req_opts(_, acc), do: acc

  defp parse_recv_opts(list) when is_list(list) do
    parse_recv_opts(list, %{timeout: @default_timeout})
  end

  defp parse_recv_opts([{:timeout, timeout} | t], acc) do
    parse_recv_opts(t, Map.put(acc, :timeout, timeout))
  end

  defp parse_recv_opts([{:deadline, deadline} | t], acc) do
    parse_recv_opts(t, Map.put(acc, :deadline, GRPC.TimeUtils.to_relative(deadline)))
  end

  defp parse_recv_opts([{:return_headers, return_headers} | t], acc) do
    parse_recv_opts(t, Map.put(acc, :return_headers, return_headers))
  end

  defp parse_recv_opts([{key, _} | _], _) do
    raise ArgumentError, "option #{inspect(key)} is not supported"
  end

  defp parse_recv_opts(_, acc), do: acc
end
