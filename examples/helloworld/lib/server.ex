defmodule Helloworld.Greeter.Server do
  use GRPC.Server, service: Helloworld.Greeter.Service

  @spec say_hello(Helloworld.HelloRequest.t(), GRPC.Server.Stream.t()) ::
          Helloworld.HelloReply.t()
  def say_hello(%{name: "quota_failure:" <> name}, stream) do
    bin = Google.Rpc.QuotaFailure.new(
      violations: [%{subject: "name:#{name}", description: "Limit one greeting per person"}]
    )
    |> Protobuf.encode()
    details = Google.Protobuf.Any.new(type_url: "type.googleapis.com/google.rpc.QuotaFailure", value: bin)
    |> Protobuf.encode()
    stream = GRPC.Server.set_headers(stream, %{"grpc-status-details-bin" => details})
    raise GRPC.RPCError, status: GRPC.Status.resource_exhausted()
  end

  def say_hello(request, _stream) do
    Helloworld.HelloReply.new(message: "Hello #{request.name}")
  end
end
