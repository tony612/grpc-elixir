defmodule RouteGuide.DataHelper do

  alias Poison.Parser

  @json_path Path.expand("../../priv/geographic_coordinates.json", __DIR__)

  def start_link do
    locations = _load_locations()
    Agent.start_link(fn -> %{locations: locations, notes: %{}} end, name: __MODULE__)
  end

  def fetch_locations do
    Agent.get(__MODULE__, &Map.get(&1, :locations))
  end

  def fetch_notes do
    Agent.get(__MODULE__, &Map.get(&1, :notes))
  end

  def update_notes(notes) do
    Agent.update(__MODULE__, &Map.put(&1, :notes, notes))
  end

  defp _load_locations(path \\ @json_path) do
    path
    |> File.read!()
    |> Parser.parse!()
    |> Enum.map(fn %{"coordinate" => coordinate, "name" => name} ->
      Location.new(
        name: name,
        coordinate: Coordinate.new(
          latitude: coordinate["latitude"],
          longitude: coordinate["longitude"]
        )
      )
    end)
  end
end
