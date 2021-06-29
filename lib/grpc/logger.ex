defmodule GRPC.Logger.Server do
  @moduledoc """
  Print log around server rpc calls, like:

      17:18:45.151 [info]  Handled by HelloServer.say_hello
      17:18:45.151 [info]  Response :ok in 11µs

  ## Usage

      defmodule Your.Endpoint do
        use GRPC.Endpoint

        intercept GRPC.Logger.Server, level: :info
      end
  """
  require Logger
  @behaviour GRPC.ServerInterceptor

  def init(opts) do
    Keyword.get(opts, :level, :info)
  end

  def call(req, stream, next, level) do
    if Logger.compare_levels(level, Logger.level()) != :lt do
      Logger.metadata(request_id: stream.request_id)
      Logger.log(level, fn ->
        ["Handled by ", inspect(stream.server), ".", to_string(elem(stream.rpc, 0))]
      end)

      start = System.monotonic_time()
      result = next.(req, stream)
      stop = System.monotonic_time()

      status = elem(result, 0)

      Logger.log(level, fn ->
        diff = System.convert_time_unit(stop - start, :native, :microsecond)

        ["Response ", inspect(status), " in ", formatted_diff(diff)]
      end)

      result
    else
      next.(req, stream)
    end
  end

  def formatted_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string(), "ms"]
  def formatted_diff(diff), do: [Integer.to_string(diff), "µs"]
end

defmodule GRPC.Logger.Client do
  require Logger

  @moduledoc """
  Print log around client rpc calls, like

      17:13:33.021 [info]  Call say_hello of helloworld.Greeter
      17:13:33.079 [info]  Got :ok in 58ms

  ## Usage

      {:ok, channel} = GRPC.Stub.connect("localhost:50051", interceptors: [GRPC.Logger.Client])
      {:ok, channel} = GRPC.Stub.connect("localhost:50051", interceptors: [{GRPC.Logger.Client, level: :info}])
  """

  def init(opts) do
    Keyword.get(opts, :level, :info)
  end

  def call(%{grpc_type: grpc_type} = stream, req, next, level) do
    if Logger.compare_levels(level, Logger.level()) != :lt do
      Logger.log(level, fn ->
        ["Call ", to_string(elem(stream.rpc, 0)), " of ", stream.service_name]
      end)

      start = System.monotonic_time()
      result = next.(stream, req)
      stop = System.monotonic_time()

      if grpc_type == :unary do
        status = elem(result, 0)

        Logger.log(level, fn ->
          diff = System.convert_time_unit(stop - start, :native, :microsecond)

          ["Got ", inspect(status), " in ", GRPC.Logger.Server.formatted_diff(diff)]
        end)
      end

      result
    else
      next.(stream, req)
    end
  end
end
