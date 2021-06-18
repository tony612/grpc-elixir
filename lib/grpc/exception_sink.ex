defmodule GRPC.ExceptionSink do
  @moduledoc """
  Exception sink for the server side. See `GRPC.Endpoint`.
  """

  @type options :: any
  @type error :: any
  @type stack_trace :: any

  @callback init(options) :: options
  @callback error(error, stack_trace) :: nil
end
