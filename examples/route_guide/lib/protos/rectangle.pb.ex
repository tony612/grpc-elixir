defmodule Rectangle do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          lo: Coordinate.t() | nil,
          hi: Coordinate.t() | nil
        }
  defstruct [:lo, :hi]

  field :lo, 1, type: Coordinate
  field :hi, 2, type: Coordinate
end
