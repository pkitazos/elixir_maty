defmodule Maty.ST do
  @moduledoc """
  Maty-specific extensions to `ST` (from the `st_parser` package).

  Defines `SBottom` for representing fully consumed session types,
  and the utility function `repr/1` used by the typechecker.
  """

  defmodule SBottom do
    @moduledoc """
    Represents a fully consumed session type (bottom).

    Produced after a handler terminates via done or suspend.
    With `reason: :nothing` it is the state of code that has no session (function and `fn` bodies).
    """
    @enforce_keys [:reason]
    defstruct [:reason]

    @type t :: %__MODULE__{
            # :done / :suspend - the session ended there
            # :nothing - there is no session
            reason: :done | :suspend | :nothing
          }
  end

  @type t :: ST.t() | SBottom.t()

  def repr(%SBottom{reason: :nothing}), do: "no session"
  def repr(%SBottom{reason: reason}), do: "⊥ (after #{reason})"
  def repr(%ST.SEnd{}), do: "end"
  def repr(%ST.SName{handler: handler}), do: Atom.to_string(handler)

  def repr(%ST.SBranch{label: label, payload: payload, continue_as: st}) do
    label_str = Atom.to_string(label)
    payload_str = Atom.to_string(payload)

    "#{label_str}(#{payload_str}).#{repr(st)}"
  end

  def repr(%ST.SOut{to: to, branches: branches}) do
    to_str = Atom.to_string(to)
    branches_str = branches |> Enum.map(&repr/1) |> Enum.join(", ")

    "#{to_str}+{#{branches_str}}"
  end

  def repr(%ST.SIn{from: from, branches: branches}) do
    from_str = Atom.to_string(from)
    branches_str = branches |> Enum.map(&repr/1) |> Enum.join(", ")

    "#{from_str}&{#{branches_str}}"
  end
end
