defmodule Routeguide.RouteGuide.Server do
  use GRPC.Server, service: Routeguide.RouteGuide.Service

  alias GRPC.Server
  alias GRPC.Server.Stream
  alias RouteGuide.DataHelper

  @doc """
  Unary RPC

  Search for a place by its coordinates
  """
  @spec get_location(Coordinate.t, Stream.t()) :: Location.t()
  def get_location(coordinate, _stream) do
    locations = DataHelper.fetch_locations()

    Enum.find(locations, Location.new(coordinate: coordinate), fn location ->
      location.coordinate == coordinate
    end)
  end

  @doc """
  Server streaming RPC

  Search for places within an imaginary coordinate rectangle
  """
  @spec list_locations(Rectangle.t(), Stream.t()) :: any
  def list_locations(rect, stream) do
    locations = DataHelper.fetch_locations()

    locations
    |> Enum.filter(fn %{coordinate: coord} -> _in_range?(coord, rect) end)
    |> Enum.each(fn location -> Server.send_reply(stream, location) end)
  end

  @doc """
  Client streaming RPC

  Process a set of coordinates to find their location and calculate
  the distance between them
  """
  @spec record_route(Enumerable.t(), GRPC.Server.Stream.t()) :: RouteSummary.t()
  def record_route(req_enum, _stream) do
    locations = DataHelper.fetch_locations()

    start_time = _unix_time()

    {_, distance, c_count, l_count} =
      Enum.reduce(req_enum, {nil, 0, 0, 0}, fn coord, {last, distance, c_count, l_count} ->
        location = Enum.find(locations, fn l -> l.coordinate == coord end)

        l_count = if location == nil, do: l_count, else: l_count + 1
        distance = if last, do: distance + _calc_distance(last, coord), else: distance

        {coord, distance, c_count + 1, l_count}
      end)

    RouteSummary.new(
      coordinate_count: c_count,
      locations_found: l_count,
      distance: distance,
      elapsed_time: _unix_time() - start_time
    )
  end

  @doc """
  Bidirectional streaming RPC

  Sort a RouteNote list by its coordinates and store the state using an Agent

  Example:

  %{
    "0 1" => [
      %RouteNote{location: <latitude: 0, longitude: 1>, message: "First message"},
      %RouteNote{location: <latitude: 0, longitude: 1>, message: "Fourth message"}
    ],
    "0 2" => [
      %RouteNote{location: <latitude: 0, longitude: 2>, message: "Second message"}
    ]
  }
  """
  @spec route_chat(Enumerable.t(), Stream.t()) :: any
  def route_chat(req_enum, stream) do
    req_enum
    |> Enum.reduce(DataHelper.fetch_notes(), fn note, acc ->
      coord = "#{note.coordinate.latitude} #{note.coordinate.longitude}"

      sort_notes = Map.update(acc, coord, [note], &(&1 ++ [note]))

      Enum.each(sort_notes[coord], fn note ->
        Server.send_reply(stream, note)
      end)

      sort_notes
    end)
    |> DataHelper.update_notes()
  end

  # ---------------------------------------------------------------------------
  # Validate if a coordinate is inside an imaginary coordinate rectangle
  # ---------------------------------------------------------------------------
  @spec _in_range?(map, map) :: boolean
  defp _in_range?(%{longitude: long, latitude: lat}, %{lo: low, hi: high}) do
    left = min(low.longitude, high.longitude)
    right = max(low.longitude, high.longitude)
    bottom = min(low.latitude, high.latitude)
    top = max(low.latitude, high.latitude)

    long >= left && long <= right && lat >= bottom && lat <= top
  end

  @spec _unix_time() :: integer
  defp _unix_time(), do: DateTime.to_unix(DateTime.utc_now)

  # ---------------------------------------------------------------------------
  # Calculates the distance between two points using the "haversine" formula.
  # This code was taken from http://www.movable-type.co.uk/scripts/latlong.html.
  # ---------------------------------------------------------------------------
  @spec _calc_distance(Coordenate.t, Coordenate.t) :: number
  defp _calc_distance(coord1, coord2) do
    cord_factor = 1.0e7
    r = 6_371_000.0

    lat1 = (coord1.latitude || 0) / cord_factor
    lat2 = (coord2.latitude || 0) / cord_factor
    lng1 = (coord1.longitude || 0) / cord_factor
    lng2 = (coord2.longitude || 0) / cord_factor

    phi1 = _to_radians(lat1)
    phi2 = _to_radians(lat2)
    delta_phi = _to_radians(lat2 - lat1)
    delta_lambda = _to_radians(lng2 - lng1)

    a = _sqr(:math.sin(delta_phi / 2)) + :math.cos(phi1) * :math.cos(phi2) * _sqr(:math.sin(delta_lambda / 2))

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    round(r * c)
  end

  @spec _to_radians(number) :: number
  defp _to_radians(num), do: num * :math.pi() / 180

  @spec _sqr(number) :: number
  defp _sqr(num), do: num * num
end
