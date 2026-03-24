defmodule Relayixir.Proxy.WebSocket.Frame do
  @moduledoc """
  Normalized WebSocket frame representation.
  """

  @type frame_type :: :text | :binary | :ping | :pong | :close

  @type t :: %__MODULE__{
          type: frame_type(),
          payload: binary() | nil,
          close_code: non_neg_integer() | nil,
          close_reason: binary() | nil
        }

  defstruct [:type, :payload, :close_code, :close_reason]

  def text(payload), do: %__MODULE__{type: :text, payload: payload}
  def binary(payload), do: %__MODULE__{type: :binary, payload: payload}
  def ping(payload \\ ""), do: %__MODULE__{type: :ping, payload: payload}
  def pong(payload \\ ""), do: %__MODULE__{type: :pong, payload: payload}

  def close(code \\ 1000, reason \\ "") do
    %__MODULE__{type: :close, close_code: code, close_reason: reason}
  end

  @doc """
  Converts a Mint.WebSocket frame tuple to a Frame struct.
  """
  def from_mint({:text, payload}), do: text(payload)
  def from_mint({:binary, payload}), do: binary(payload)
  def from_mint({:ping, payload}), do: ping(payload)
  def from_mint({:pong, payload}), do: pong(payload)
  def from_mint({:close, code, reason}), do: close(code, reason)
  def from_mint(:close), do: close(1000, "")

  @doc """
  Converts a Frame struct to a Mint.WebSocket frame tuple.
  """
  def to_mint(%__MODULE__{type: :text, payload: payload}), do: {:text, payload}
  def to_mint(%__MODULE__{type: :binary, payload: payload}), do: {:binary, payload}
  def to_mint(%__MODULE__{type: :ping, payload: payload}), do: {:ping, payload}
  def to_mint(%__MODULE__{type: :pong, payload: payload}), do: {:pong, payload}

  def to_mint(%__MODULE__{type: :close, close_code: code, close_reason: reason}),
    do: {:close, code, reason}

  @doc """
  Converts a Frame struct to a Bandit/WebSock frame tuple.
  """
  def to_websock(%__MODULE__{type: :text, payload: payload}), do: {:text, payload}
  def to_websock(%__MODULE__{type: :binary, payload: payload}), do: {:binary, payload}
  def to_websock(%__MODULE__{type: :ping, payload: payload}), do: {:ping, payload}
  def to_websock(%__MODULE__{type: :pong, payload: payload}), do: {:pong, payload}

  def to_websock(%__MODULE__{type: :close, close_code: code, close_reason: reason}),
    do: {:close, code, reason}

  @doc """
  Converts a Bandit/WebSock incoming frame to a Frame struct.
  """
  def from_websock({:text, payload}), do: text(payload)
  def from_websock({:binary, payload}), do: binary(payload)
  def from_websock({:ping, payload}), do: ping(payload)
  def from_websock({:pong, payload}), do: pong(payload)
end
