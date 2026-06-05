defmodule Maty.ST do
  alias Maty.ST

  @moduledoc """
  Defines the core data structures for Session Types.

  Session Types (ST) provide a formal way to describe communication protocols
  between different roles in a distributed system. This module defines the
  data structures that represent these session types after parsing.

  The main session type constructs are:
  - `SIn` - For receiving messages (external choice)
  - `SOut` - For sending messages (internal choice)
  - `SEnd` - For terminating a session

  Each of these has convenience constructor functions available in this module.
  """

  defmodule SBranch do
    @moduledoc """
    Represents a single branch in a choice or a single action sequence.

    Each branch has a label, a payload type, and a continuation session type.
    """
    @enforce_keys [:label, :payload, :continue_as]
    defstruct [:label, :payload, :continue_as]

    @typedoc """
    A branch containing:
    - label: The message label as a snake_case atom
    - payload: The payload type of the message
    - continue_as: The continuation session type after this branch
    """
    @type t :: %__MODULE__{
            label: atom(),
            payload: ST.payload_type(),
            continue_as: ST.t()
          }
  end

  defmodule SIn do
    @moduledoc """
    Represents receiving messages (external choice).

    This session type indicates that the current role is expecting to
    receive one of several possible messages from another role.
    """
    @enforce_keys [:from, :branches]
    defstruct [:from, :branches]

    @typedoc """
    An input session type containing:
    - from: The role sending the message(s) as a snake_case atom
    - branches: List of possible message branches that can be received
    """
    @type t :: %__MODULE__{
            from: atom(),
            branches: [SBranch.t()]
          }
  end

  defmodule SOut do
    @moduledoc """
    Represents sending messages (internal choice).

    This session type indicates that the current role will send
    one of several possible messages to another role.
    """
    @enforce_keys [:to, :branches]
    defstruct [:to, :branches]

    @typedoc """
    An output session type containing:
    - to: The role receiving the message(s) as a snake_case atom
    - branches: List of possible message branches that can be sent
    """
    @type t :: %__MODULE__{
            to: atom(),
            branches: [SBranch.t()]
          }
  end

  defmodule SEnd do
    @moduledoc """
    Represents the termination of a session path.

    This indicates that the communication on this particular path has ended.
    """
    defstruct []

    @typedoc """
    An end session type marker (empty struct)
    """
    @type t :: %__MODULE__{}
  end

  defmodule SName do
    @moduledoc """
    Represents a named handler reference in a session type.

    This session type indicates that the current role will delegate
    processing to a specific named handler function.
    """
    @enforce_keys [:handler]
    defstruct [:handler]

    @typedoc """
    A named handler reference containing:
    - handler: The name of the handler function as an atom
    """
    @type t :: %__MODULE__{
            handler: atom()
          }
  end

  defmodule SBottom do
    @moduledoc """
    Represents a fully consumed session type (bottom).

    Produced after a handler terminates via done or suspend.
    """
    @enforce_keys [:reason]
    defstruct [:reason]

    @type t :: %__MODULE__{
            reason: :done | :suspend | :nothing
          }
  end

  @typedoc """
  A session type that can be:
  - An input type (receiving messages)
  - An output type (sending messages)
  - A termination marker
  - A named handler reference
  - A bottom type (fully consumed session)
  """
  @type t :: SIn.t() | SOut.t() | SEnd.t() | SName.t() | SBottom.t()

  @typedoc """
  A payload type that can be:
  - A basic type (:binary, :number, :boolean, nil)
  - A list of a basic type
  - A tuple containing multiple payload types
  """
  @type payload_type :: atom() | {:list, [atom()]} | {:tuple, [payload_type()]}

  @doc """
  Creates a branch in a session type.

  ## Parameters
  - `label`: The message label (atom)
  - `payload`: The payload type
  - `continue_as`: The continuation session type

  ## Example
      iex> ST.branch(:request, :binary, %ST.SEnd{})
      %ST.SBranch{
        label: :request,
        payload: :binary,
        continue_as: %ST.SEnd{}
      }
  """
  @spec branch(atom(), payload_type(), t()) :: SBranch.t()
  def branch(label, payload, continue_as) do
    %SBranch{
      label: label,
      payload: payload,
      continue_as: continue_as
    }
  end

  @doc """
  Creates an input session type (for receiving messages).

  ## Parameters
  - `from`: The role sending the message(s)
  - `branches`: List of possible branches that can be received

  ## Example
      iex> branch = ST.branch(:ack, nil, %ST.SEnd{})
      iex> ST.input(:server, [branch])
      %ST.SIn{
        from: :server,
        branches: [%ST.SBranch{
          label: :ack,
          payload: nil,
          continue_as: %ST.SEnd{}
        }]
      }
  """
  @spec input(atom(), [SBranch.t()]) :: SIn.t()
  def input(from, branches) when is_list(branches) do
    %SIn{
      from: from,
      branches: branches
    }
  end

  @doc """
  Convenience function to create an input with a single branch.

  ## Parameters
  - `from`: The role sending the message
  - `label`: The message label
  - `payload`: The payload type
  - `continue_as`: The continuation session type

  ## Example
      iex> ST.input_one(:server, :ack, nil, %ST.SEnd{})
      %ST.SIn{
        from: :server,
        branches: [%ST.SBranch{
          label: :ack,
          payload: nil,
          continue_as: %ST.SEnd{}
        }]
      }
  """
  @spec input_one(atom(), atom(), payload_type(), t()) :: SIn.t()
  def input_one(from, label, payload, continue_as) do
    input(from, [branch(label, payload, continue_as)])
  end

  @doc """
  Creates an output session type (for sending messages).

  ## Parameters
  - `to`: The role receiving the message(s)
  - `branches`: List of possible branches that can be sent

  ## Example
      iex> branch = ST.branch(:request, :binary, %ST.SEnd{})
      iex> ST.output(:client, [branch])
      %ST.SOut{
        to: :client,
        branches: [%ST.SBranch{
          label: :request,
          payload: :binary,
          continue_as: %ST.SEnd{}
        }]
      }
  """
  @spec output(atom(), [SBranch.t()]) :: SOut.t()
  def output(to, branches) when is_list(branches) do
    %SOut{
      to: to,
      branches: branches
    }
  end

  @doc """
  Convenience function to create an output with a single branch.

  ## Parameters
  - `to`: The role receiving the message
  - `label`: The message label
  - `payload`: The payload type
  - `continue_as`: The continuation session type

  ## Example
      iex> ST.output_one(:client, :request, :binary, %ST.SEnd{})
      %ST.SOut{
        to: :client,
        branches: [%ST.SBranch{
          label: :request,
          payload: :binary,
          continue_as: %ST.SEnd{}
        }]
      }
  """
  @spec output_one(atom(), atom(), payload_type(), t()) :: SOut.t()
  def output_one(to, label, payload, continue_as) do
    output(to, [branch(label, payload, continue_as)])
  end

  @doc """
  Creates an end session type.

  ## Example
      iex> ST.end_session()
      %ST.SEnd{}
  """
  @spec end_session() :: SEnd.t()
  def end_session do
    %SEnd{}
  end

  @doc """
  Creates a named handler reference.

  ## Parameters
  - `handler`: The handler function name (atom)

  ## Example
      iex> ST.name(:quote_handler)
      %ST.SName{
        handler: :quote_handler
      }
  """
  @spec name(atom()) :: SName.t()
  def name(handler) do
    %SName{
      handler: handler
    }
  end

  def repr(%SEnd{}), do: "end"
  def repr(%SName{handler: handler}), do: Atom.to_string(handler)

  def repr(%SBranch{label: label, payload: payload, continue_as: st}) do
    label_str = Atom.to_string(label)
    payload_str = Atom.to_string(payload)

    "#{label_str}(#{payload_str}).#{repr(st)}"
  end

  def repr(%SOut{to: to, branches: branches}) do
    to_str = Atom.to_string(to)
    branches_str = branches |> Enum.map(&repr/1) |> Enum.join(", ")

    "#{to_str}+{#{branches_str}}"
  end

  def repr(%SIn{from: from, branches: branches}) do
    from_str = Atom.to_string(from)
    branches_str = branches |> Enum.map(&repr/1) |> Enum.join(", ")

    "#{from_str}&{#{branches_str}}"
  end

  def get_action(%SEnd{}), do: :done
  def get_action(%SName{}), do: :suspend
  def get_action(%SOut{}), do: :send
  def get_action(%SIn{}), do: :receive
  def get_action(%SBranch{}), do: :error
end
