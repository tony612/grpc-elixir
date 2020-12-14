defmodule Coordinate do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          latitude: integer,
          longitude: integer
        }
  defstruct [:latitude, :longitude]

  field :latitude, 1, type: :int32
  field :longitude, 2, type: :int32
end
