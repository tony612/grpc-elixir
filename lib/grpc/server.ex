defmodule GRPC.Server do
  @moduledoc """
  A gRPC server which handles requests by calling user-defined functions.

  You should pass a `GRPC.Service` in when *use* the module:

      defmodule Greeter.Service do
        use GRPC.Service, name: "ping"

        rpc :SayHello, Request, Reply
        rpc :SayGoodbye, stream(Request), stream(Reply)
      end

      defmodule Greeter.Server do
        use GRPC.Server, service: Greeter.Service

        def say_hello(request, _stream) do
          Reply.new(message: "Hello")
        end

        def say_goodbye(request_enum, stream) do
          requests = Enum.map request_enum, &(&1)
          GRPC.Server.send_reply(stream, reply1)
          GRPC.Server.send_reply(stream, reply2)
        end
      end

  Your functions should accept a client request and a `GRPC.Server.Stream`.
  The request will be a `Enumerable.t`(created by Elixir's `Stream`) of requests
  if it's streaming. If a reply is streaming, you need to call `send_reply/2` to send
  replies one by one instead of returning reply in the end.
  """

  require Logger

  alias GRPC.RPCError
  alias GRPC.ServerAdapter

  @type rpc_req :: struct | Enumerable.t()
  @type rpc_return :: struct | any
  @type rpc :: (GRPC.Server.rpc_req(), stream -> rpc_return)

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      service_mod = opts[:service]
      service_name = service_mod.__meta__(:name)
      codecs = opts[:codecs] || [GRPC.Codec.Proto]
      compressors = opts[:compressors] || []

      Enum.each(service_mod.__rpc_calls__, fn {name, _, _} = rpc ->
        func_name = name |> to_string |> Macro.underscore() |> String.to_atom()
        path = "/#{service_name}/#{name}"
        grpc_type = GRPC.Service.grpc_type(rpc)

        def __call_rpc__(unquote(path), stream) do
          GRPC.Server.call(
            unquote(service_mod),
            %{
              stream
              | service_name: unquote(service_name),
                method_name: unquote(to_string(name)),
                grpc_type: unquote(grpc_type)
            },
            unquote(Macro.escape(put_elem(rpc, 0, func_name))),
            unquote(func_name)
          )
        end
      end)

      def __call_rpc__(_, stream) do
        raise GRPC.RPCError, status: :unimplemented
      end

      def __meta__(:service), do: unquote(service_mod)
      def __meta__(:codecs), do: unquote(codecs)
      def __meta__(:compressors), do: unquote(compressors)
    end
  end

  @type endpoint :: ServerAdapter.endpoint()
  @type server_port :: ServerAdapter.server_port()
  @type servers_list :: module | [module]
  @type servers_map :: ServerAdapter.servers_map()
  @type stream :: ServerAdapter.stream()
  @type headers :: ServerAdapter.headers()

  @doc false
  @spec call(atom, stream, tuple, atom) :: {:ok, stream, struct} | {:ok, struct}
  def call(
        _service_mod,
        stream,
        {_, {req_mod, req_stream}, {res_mod, res_stream}} = rpc,
        func_name
      ) do
    stream = %{stream | request_mod: req_mod, response_mod: res_mod, rpc: rpc}

    handle_request(req_stream, res_stream, stream, func_name)
  end

  defp handle_request(req_s, res_s, %{server: server} = stream, func_name) do
    if function_exported?(server, func_name, 2) do
      do_handle_request(req_s, res_s, stream, func_name)
    else
      {:error, GRPC.RPCError.new(:unimplemented)}
    end
  end

  defp do_handle_request(
         false,
         res_stream,
         %{request_mod: req_mod, codec: codec, adapter: adapter, payload: payload} = stream,
         func_name
       ) do
    {:ok, data} = adapter.read_body(payload)

    case GRPC.Message.from_data(stream, data) do
      {:ok, message} ->
        request = codec.decode(message, req_mod)

        call_with_interceptors(res_stream, func_name, stream, request)

      resp = {:error, _} ->
        resp
    end
  end

  defp do_handle_request(
         true,
         res_stream,
         %{
           request_mod: req_mod,
           codec: codec,
           adapter: adapter,
           payload: payload,
           compressor: compressor
         } = stream,
         func_name
       ) do
    reading_stream =
      adapter.reading_stream(payload)
      |> Elixir.Stream.map(fn {flag, message} ->
        cond do
          flag == 0 ->
            codec.decode(message, req_mod)

          flag == 1 && compressor != nil ->
            compressor.decompress(message)
            |> codec.decode(req_mod)

          flag == 1 && compressor == nil ->
            raise RPCError.exception(
                    status: :invalid_argument,
                    message: "grpc encoding is specified, but message is not compressed"
                  )
        end
      end)

    call_with_interceptors(res_stream, func_name, stream, reading_stream)
  end

  defp call_with_interceptors(
         res_stream,
         func_name,
         %{server: server, endpoint: endpoint} = stream,
         req
       ) do
    last = fn r, s ->
      reply = apply(server, func_name, [r, s])

      if res_stream do
        {:ok, stream}
      else
        {:ok, stream, reply}
      end
    end

    interceptors = interceptors(endpoint, server)

    next =
      Enum.reduce(interceptors, last, fn {interceptor, opts}, acc ->
        fn r, s -> interceptor.call(r, s, acc, opts) end
      end)

    try do
      next.(req, stream)
    rescue
      e in GRPC.RPCError ->
        {:error, e}
    catch
      kind, reason ->
        stack = __STACKTRACE__
        Logger.error(Exception.format(kind, reason, stack))
        reason = Exception.normalize(kind, reason, stack)
        {:error, %{kind: kind, reason: reason, stack: stack}}
    end
  end

  defp interceptors(nil, _), do: []

  defp interceptors(endpoint, server) do
    interceptors =
      endpoint.__meta__(:interceptors) ++
        Map.get(endpoint.__meta__(:server_interceptors), server, [])

    interceptors |> Enum.reverse()
  end

  # Start the gRPC server. Only used in starting a server manually using `GRPC.Server.start(servers)`
  #
  # A generated `port` will be returned if the port is `0`.
  #
  # ## Examples
  #
  #     iex> {:ok, _, port} = GRPC.Server.start(Greeter.Server, 50051)
  #     iex> {:ok, _, port} = GRPC.Server.start(Greeter.Server, 0, ip: {:local, "path/to/unix.sock"})
  #
  # ## Options
  #
  #   * `:cred` - a credential created by functions of `GRPC.Credential`,
  #               an insecure server will be created without this option
  #   * `:adapter` - use a custom server adapter instead of default `GRPC.Adapter.Cowboy`
  @doc false
  @spec start(servers_list, server_port, Keyword.t()) :: {atom, any, non_neg_integer}
  def start(servers, port, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, GRPC.Adapter.Cowboy)
    servers = GRPC.Server.servers_to_map(servers)
    adapter.start(nil, servers, port, opts)
  end

  @doc false
  @spec start_endpoint(endpoint, server_port, Keyword.t()) :: {atom, any, non_neg_integer}
  def start_endpoint(endpoint, port, opts \\ []) do
    servers = endpoint.__meta__(:servers)
    servers = GRPC.Server.servers_to_map(servers)
    adapter = Keyword.get(opts, :adapter, GRPC.Adapter.Cowboy)
    adapter.start(endpoint, servers, port, opts)
  end

  # Stop the server
  #
  # ## Examples
  #
  #     iex> GRPC.Server.stop(Greeter.Server)
  #
  # ## Options
  #
  #   * `:adapter` - use a custom adapter instead of default `GRPC.Adapter.Cowboy`
  @doc false
  @spec stop(servers_list, Keyword.t()) :: any
  def stop(servers, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, GRPC.Adapter.Cowboy)
    servers = GRPC.Server.servers_to_map(servers)
    adapter.stop(nil, servers)
  end

  @doc false
  @spec stop_endpoint(endpoint, Keyword.t()) :: any
  def stop_endpoint(endpoint, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, GRPC.Adapter.Cowboy)
    servers = endpoint.__meta__(:servers)
    servers = GRPC.Server.servers_to_map(servers)
    adapter.stop(endpoint, servers)
  end

  @doc """
  DEPRECATED. Use `send_reply/3` instead
  """
  @deprecated "Use send_reply/3 instead"
  def stream_send(stream, reply) do
    send_reply(stream, reply)
  end

  @doc """
  Send streaming reply.

  ## Examples

      iex> GRPC.Server.send_reply(stream, reply)
  """
  @spec send_reply(stream, struct) :: stream
  def send_reply(%{__interface__: interface} = stream, reply, opts \\ []) do
    interface[:send_reply].(stream, reply, opts)
  end

  @doc """
  Send custom metadata(headers).

  You can send headers only once, before that you can set headers using `set_headers/2`.
  """
  @spec send_headers(stream, headers) :: stream
  def send_headers(%{adapter: adapter} = stream, headers) do
    adapter.send_headers(stream.payload, headers)
    stream
  end

  @doc """
  Set custom metadata(headers).

  You can set headers more than once.
  """
  @spec set_headers(stream, headers) :: stream
  def set_headers(%{adapter: adapter} = stream, headers) do
    adapter.set_headers(stream.payload, headers)
    stream
  end

  @doc """
  Set custom trailers, which will be sent in the end.
  """
  @spec set_trailers(stream, headers) :: stream
  def set_trailers(%{adapter: adapter} = stream, trailers) do
    adapter.set_resp_trailers(stream.payload, trailers)
    stream
  end

  @doc """
  Set compressor to compress responses. An accepted compressor will be set if clients use one,
  even if `set_compressor` is not called. But this can be called to override the chosen.
  """
  @spec set_compressor(stream, module) :: stream
  def set_compressor(%{adapter: adapter} = stream, compressor) do
    adapter.set_compressor(stream.payload, compressor)
    stream
  end

  @doc false
  def send_trailers(%{adapter: adapter} = stream, trailers) do
    adapter.send_trailers(stream.payload, trailers)
    stream
  end

  @doc false
  @spec service_name(String.t()) :: String.t()
  def service_name(path) do
    ["", name | _] = String.split(path, "/")
    name
  end

  @doc false
  @spec servers_to_map(servers_list) :: servers_map
  def servers_to_map(servers) do
    Enum.reduce(List.wrap(servers), %{}, fn s, acc ->
      Map.put(acc, s.__meta__(:service).__meta__(:name), s)
    end)
  end
end
