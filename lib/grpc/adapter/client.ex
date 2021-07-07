defmodule GRPC.ClientAdapter do
  @moduledoc false

  alias GRPC.Client.Stream
  alias GRPC.Channel

  @type opts :: any

  @type channel :: Channel.t()
  @callback connect(channel, opts) :: {:ok, channel} | {:error, any}

  @type stream :: Stream.t()
  @type message :: binary()
  @callback send_request(stream, message, opts) :: stream

  @type headers :: [{String.t(), String.t()}]
  @type fin :: :fin | :nofin
  @callback recv_headers(map(), map(), opts) ::
              {:ok, headers, fin} | {:error, GRPC.RPCError.t()}

  @type data :: binary()
  @type trailers :: binary()
  @callback recv_data_or_trailers(map(), map(), opts) ::
              {:data, data} | {:trailers, trailers} | {:error, GRPC.RPCError.t()}
end
