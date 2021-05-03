defmodule GRPC.MessageTest do
  use ExUnit.Case, async: true

  doctest GRPC.Message

  test "compressor works" do
    message = String.duplicate("foo", 100)

    # 10th byte is the operating system ID
    assert {:ok,
            data =
              <<1, 0, 0, 0, 27, 31, 139, 8, 0, 0, 0, 0, 0, 0, _, 75, 203, 207, 79, 27, 69, 196,
                33, 0, 41, 249, 122, 62, 44, 1, 0, 0>>,
            32} = GRPC.Message.to_data(message, %{compressor: GRPC.Compressor.Gzip})

    assert {:ok, message} == GRPC.Message.from_data(%{compressor: GRPC.Compressor.Gzip}, data)
  end

  test "iodata can be passed to and returned from `to_data/2`" do
    message = List.duplicate("foo", 100)

    assert {:ok, data, 32} =
             GRPC.Message.to_data(message, iolist: true, compressor: GRPC.Compressor.Gzip)

    assert is_list(data)
    binary = IO.iodata_to_binary(data)

    assert {:ok, IO.iodata_to_binary(message)} ==
             GRPC.Message.from_data(%{compressor: GRPC.Compressor.Gzip}, binary)
  end
end
