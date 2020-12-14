defmodule Location do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          name: String.t(),
          coordinate: Coordinate.t() | nil
        }
  defstruct [:name, :coordinate]

  field :name, 1, type: :string
  field :coordinate, 2, type: Coordinate
end
