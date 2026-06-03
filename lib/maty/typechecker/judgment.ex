defmodule Maty.Typechecker.Judgment do
  @moduledoc """
  Shared type vocabulary for the checking phase.

  Covers the local, threaded part of  Ψ; Δ; Γ | Q₁ ⊳ e : T ⊲ Q₂ : the
  environment Γ (`var_env`) and the result every `tc_expr` clause produces and
  `TC.Bind` consumes.

  The fixed per-module part (Ψ; Δ) is `Maty.Typechecker.Ctx`.
  """
  alias Maty.ST
  alias Maty.Types.T, as: Type

  @type var_env :: %{atom() => Type.t()}

  @typedoc "A checking step producing a value of type `a`, threading env and session type."
  @type result(a) :: {:ok, {a, ST.t()}, var_env()} | {:error, term(), var_env()}

  @typedoc "What a tc_expr clause produces: the value is always an object-language type."
  @type result :: result(Type.t())
end
