defimpl Inspect, for: Point do
  def inspect(%{__struct__: struct} = point, opts) do
    lat_str = Inspect.Integer.inspect(point.latitude || 0, opts)
    lng_str = Inspect.Integer.inspect(point.longitude || 0, opts)
    middle = "latitude: " <> lat_str <> ", longitude: " <> lng_str

    if Map.get(opts, :compact, true) do
      "<" <> middle <> ">"
    else
      name = Inspect.Atom.inspect(struct, opts)
      "%#{name}{" <> middle <> "}"
    end
  end
end

defimpl Inspect, for: Feature do
  def inspect(%{__struct__: struct} = feature, opts) do
    name = Inspect.Atom.inspect(struct, opts)

    name_str =
      if feature.name do
        Inspect.BitString.inspect(feature.name, opts)
      else
        Inspect.Atom.inspect(nil, opts)
      end

    loc_str = Inspect.Point.inspect(feature.location, opts)
    middle = "name: " <> name_str <> ", location: " <> loc_str

    if Map.get(opts, :compact, true) do
      "<" <> middle <> ">"
    else
      "%#{name}{" <> middle <> "}"
    end
  end
end
