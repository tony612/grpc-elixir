defmodule Routeguide.Endpoint do
  use GRPC.Endpoint

  intercept GRPC.Logger.Server
  run Routeguide.RouteGuide.Server
end
