defmodule Routeguide.RouteGuide.Service do
  @moduledoc false
  use GRPC.Service, name: "routeguide.RouteGuide"

  rpc :GetLocation, Coordinate, Location
  rpc :ListLocations, Rectangle, stream(Location)
  rpc :RecordRoute, stream(Coordinate), RouteSummary
  rpc :RouteChat, stream(RouteNote), stream(RouteNote)
end

defmodule Routeguide.RouteGuide.Stub do
  @moduledoc false
  use GRPC.Stub, service: Routeguide.RouteGuide.Service
end
