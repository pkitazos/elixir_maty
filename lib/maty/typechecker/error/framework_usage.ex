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

  def missing_session_registration(module) do
    %Error{
      category: :framework_usage,
      kind: :missing_session_registration,
      module: module
    }
  end

  def on_link_altered_session_state(module, got_st) do
    %Error{
      category: :framework_usage,
      kind: :on_link_altered_session_state,
      module: module,
      details: %{got: got_st}
    }
  end

  # MATY_ERROR_KIND_REVIEW
  # this is also arguably a :type_mismatch since it gets returned when
  # the on_link/2 return value has the wrong type.
  # I currently went with :framework_usage because it's also about the on_link callback contract, not sure.
  # Should have a look at other library code to see
  def on_link_bad_return(module, got) do
    %Error{
      category: :framework_usage,
      kind: :on_link_bad_return,
      module: module,
      details: %{got: got}
    }
  end

  # MATY_ERROR_KIND_REVIEW
  # the whole register / init_handler path needs rework
  # init_handlers are passed as references which would be okay,
  # BUT anonymous functions aren't really supported yet (see todos in tc.ex)
  # marked as :framework_usage for now, though its home and shape are likely to change.
  def invalid_init_handler(module, meta) do
    %Error{
      category: :framework_usage,
      kind: :invalid_init_handler,
      module: module,
      meta: Keyword.take(meta, [:line, :column])
    }
  end
end
