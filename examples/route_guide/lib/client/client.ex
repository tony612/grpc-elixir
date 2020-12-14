defmodule RouteGuide.Client do

  alias Routeguide.RouteGuide.Stub
  alias GRPC.Server.Stream

  require Logger

  def main(conn) do
    Logger.info "----------------------------------------------------"
    Logger.info "Unary Request (Search for a place by its coordinates)"
    Logger.info "----------------------------------------------------"

    request("unary", conn, _set_coordinate(409_146_138, -746_188_906))
    request("unary", conn, _set_coordinate(0, 0))

    Logger.info "----------------------------------------------------"
    Logger.info "Server streaming Request"
    Logger.info "----------------------------------------------------"

    # Looking for places between 40, -75 and 42, -73.
    rectangle = Rectangle.new(
      lo: _set_coordinate(400_000_000, -750_000_000),
      hi: _set_coordinate(420_000_000, -730_000_000)
    )

    request("server_streaming", conn, rectangle)

    Logger.info "----------------------------------------------------"
    Logger.info "Client streaming Request"
    Logger.info "Send random coordinates to find their location and calculate
    the distance between them"
    Logger.info "----------------------------------------------------"

    request("client_streaming", conn)

    Logger.info "----------------------------------------------------"
    Logger.info "Bidirectional streaming Request"
    Logger.info "Sort a RouteNote list by its coordinates"
    Logger.info "----------------------------------------------------"

    request("bidirectional_streaming", conn)
  end

  @doc """
  Unary RPC
  """
  @spec request(String.t, GRPC.Channel.t) :: any
  @spec request(String.t, GRPC.Channel.t, Coordinate.t | Rectangle.t) :: any
  def request("client_streaming", conn) do
    {rand_enum, seed} = _set_rand_enum()

    {coordinates, _seed} =
      Enum.reduce(rand_enum, {[], seed}, fn _item, {acc, seed} ->
        {coordinate, seed} = _random_coordinate(seed)
        {[coordinate | acc], seed}
      end)

    Logger.info "Traversing #{length(coordinates)} coordinates."

    # Start a stream to send requests to the server
    stream = Stub.record_route(conn)

    _send_request(stream, coordinates)

    # Receive a replie when requests are streaming.
    res = GRPC.Stub.recv(stream)
    Logger.info "Route summary: #{inspect(res)}"
  end
  def request("bidirectional_streaming", conn) do
    # Start a stream to send requests to the server
    stream = Stub.route_chat(conn)

    notes =
      [
        %{lat: 0, long: 1, msg: "First message"},
        %{lat: 0, long: 2, msg: "Second message"},
        %{lat: 0, long: 3, msg: "Third message"},
        %{lat: 0, long: 1, msg: "Fourth message"},
        %{lat: 0, long: 2, msg: "Fifth message"},
        %{lat: 0, long: 3, msg: "Sixth message"}
      ]
      |> Enum.map(fn %{lat: lat, long: long, msg: msg} ->
        coord = Coordinate.new(latitude: lat, longitude: long)
        RouteNote.new(message: msg, coordinate: coord)
      end)

    task = Task.async(fn -> _send_request(stream, notes) end)

    # Receive replies when requests are streaming.
    {:ok, result} = GRPC.Stub.recv(stream)

    Task.await(task)

    Enum.each(result, fn {:ok, %RouteNote{message: msg, coordinate: coord}} ->
      Logger.info "Got message #{msg} at coordinate(#{coord.latitude}, #{coord.longitude})"
    end)
  end
  def request("server_streaming", conn, rect) do
    Logger.info("Search for places within #{inspect(rect)}")

    {:ok, stream} = Stub.list_locations(conn, rect)

    Enum.each(stream, fn {:ok, location} ->
      Logger.info "Location: #{location.name}"
    end)
  end
  def request("unary", conn, coordinate) do
    Logger.info("Getting location for coordinate (#{coordinate.latitude}, #{coordinate.longitude})")

    case Stub.get_location(conn, coordinate) do
      {:ok, %Location{name: ""}} ->
        Logger.info "Location: Not found"
      {:ok, location} ->
        Logger.info "Location: #{location.name}"
      end
  end

  # ---------------------------------------------------------------------------
  # Send request while the end of the list is not defined in the options
  # ---------------------------------------------------------------------------
  @spec _send_request(Stream.t, list) :: GRPC.Client.Stream.t()
  defp _send_request(stream, [head]) do
    GRPC.Stub.send_request(stream, head, [end_stream: true])
  end
  defp _send_request(stream, [head | tail]) do
    GRPC.Stub.send_request(stream, head, [])

    _send_request(stream, tail)
  end

  @spec _set_coordinate(integer, integer) :: Coordinate.t()
  defp _set_coordinate(lat, long), do: Coordinate.new(latitude: lat, longitude: long)

  defp _random_coordinate(seed) do
    {lat, seed} = :rand.uniform_s(seed)
    {long, seed} = :rand.uniform_s(seed)

    lat = trunc((trunc(lat * 180) - 90) * 1.0e7)
    long = trunc((trunc(long * 360) - 180) * 1.0e7)

    {Coordinate.new(latitude: lat, longitude: long), seed}
  end

  @spec _set_rand_enum() :: {list, tuple}
  defp _set_rand_enum() do
    seed = :rand.seed(:exs64, :os.timestamp())

    {count, seed} = :rand.uniform_s(seed)
    count = trunc(count * 100 + 2)
    {1..count, seed}
  end
end
