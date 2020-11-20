{:ok, channel} = GRPC.Stub.connect("localhost:50051", interceptors: [GRPC.Logger.Client])

{:error, reason, headers} =
  channel |> Helloworld.Greeter.Stub.say_hello(Helloworld.HelloRequest.new(name: "quota_failure:word"), return_headers: true)
  |> IO.inspect(label: "[#{__ENV__.file}:#{__ENV__.line}] debug print")

# IO.inspect(reply)
