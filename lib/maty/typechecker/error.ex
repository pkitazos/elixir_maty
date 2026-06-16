defmodule Maty.Typechecker.Error do
  @enforce_keys [:category, :kind]
  defstruct [:category, :kind, :module, :handler, meta: [], details: %{}, st: nil, trace: []]

  @typedoc """
  A context frame pushed onto an error's `trace` as it bubbles up through the
  typechecker, innermost first. Rendered by `Maty.Typechecker.Error.Formatter`.
  """
  @type frame ::
          {:call, {atom(), non_neg_integer()}, Keyword.t()}
          | {:clause, {atom(), non_neg_integer()}, non_neg_integer()}
          | {:case_branch, non_neg_integer(), Keyword.t()}

  @type category ::
          :protocol_violation
          | :type_mismatch
          | :pattern_matching
          | :function_call
          | :type_specification
          | :framework_usage
          | :name_resolution
          | :internal

  @type t :: %__MODULE__{
          # broad family of the error, one per Error submodule
          category: category(),
          # the specific error, one per constructor (e.g. :incorrect_message_label)
          kind: atom(),
          module: module() | nil,
          # handler-scoped errors carry the handler label instead of (or alongside) meta/line
          handler: atom() | nil,
          # normalised at construction to Keyword.take(meta, [:line, :column])
          meta: Keyword.t(),
          # kind-specific payload (got/expected/pattern/...)
          details: map(),
          # carried so the Formatter can call Maty.ST.repr/1 & get_action/1
          st: Maty.ST.t() | nil,
          # context frames, innermost first (prepended on bubble-up)
          trace: [frame()]
        }

  def internal_error(a) do
    %__MODULE__{category: :internal, kind: :internal_error, details: %{message: "#{a}"}}
  end
end
