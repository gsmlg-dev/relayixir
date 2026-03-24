defmodule Relayixir.Support.Errors do
  @moduledoc """
  Struct-based error representation with type and metadata.
  """

  defstruct [:type, metadata: %{}]

  @type t :: %__MODULE__{
          type: atom(),
          metadata: map()
        }

  @doc """
  Creates a new error struct.
  """
  def new(type, metadata \\ %{}) do
    %__MODULE__{type: type, metadata: metadata}
  end
end
