defmodule Maty.Typechecker.Error.FrameworkUsage do
  alias Maty.Typechecker.Error

  def no_native_send(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :no_native_send,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def no_native_receive(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :no_native_receive,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def unsupported_anonymous_function(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_anonymous_function,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  # bitstring syntax other than string concatenation and interpolation was used
  def unsupported_bitstring(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :unsupported_bitstring,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def missing_session_registration(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :missing_session_registration,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end

  def on_link_altered_session_state(module, meta, got_st) do
    %Error{
      category: :framework_usage,
      kind: :on_link_altered_session_state,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_st}
    }
  end

  def on_link_bad_return(module, meta, got) do
    %Error{
      category: :framework_usage,
      kind: :on_link_bad_return,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end

  # register was given an atom that does not name an init handler of this module
  def unknown_init_handler(module, meta, handler_name, known) do
    %Error{
      category: :framework_usage,
      kind: :unknown_init_handler,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: handler_name, known: known}
    }
  end

  # register was given an expression for the init handler, not a literal atom
  def init_handler_not_literal(module, meta, got_ast) do
    %Error{
      category: :framework_usage,
      kind: :init_handler_not_literal,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got_ast}
    }
  end

  # register was called with the wrong number of arguments
  def register_wrong_arity(module, meta, got) do
    %Error{
      category: :framework_usage,
      kind: :register_wrong_arity,
      module: module,
      meta: Keyword.take(meta, [:line, :column]),
      details: %{got: got}
    }
  end
end
