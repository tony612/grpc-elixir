defmodule RouteNote do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          coordinate: Coordinate.t() | nil,
          message: String.t()
        }
  defstruct [:coordinate, :message]

  field :coordinate, 1, type: Coordinate
  field :message, 2, type: :string
end

defmodule RouteSummary do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          coordinate_count: integer,
          locations_found: integer,
          distance: integer,
          elapsed_time: integer
        }
  defstruct [:coordinate_count, :locations_found, :distance, :elapsed_time]

  field :coordinate_count, 1, type: :int32
  field :locations_found, 2, type: :int32
  field :distance, 3, type: :int32
  field :elapsed_time, 4, type: :int32
end
