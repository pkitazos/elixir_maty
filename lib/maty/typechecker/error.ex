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

  def version_mismatch(expected, got) do
    "Found version #{got} but expected #{expected}."
  end

  def no_raw_receive(meta) do
    with_meta(meta, "Raw receive is not allowed in a Maty.Actor.")
  end

  def no_raw_send(meta) do
    with_meta(meta, "Raw send(...) is not allowed in a Maty.Actor.")
  end

  def unexpected do
    "an unexpected error occurred"
  end

  # -----------------------------------------------------------------

  def internal_error(a), do: "Internal Error: #{a}"

  def internal_error(a, b), do: "Internal Error: #{inspect(a)} - #{inspect(b)}"

  # -----------------------------------------------------------------

  defp with_meta(meta, str) do
    meta = Keyword.take(meta, [:line, :column])
    "#{inspect(meta)} #{str}"
  end
end
