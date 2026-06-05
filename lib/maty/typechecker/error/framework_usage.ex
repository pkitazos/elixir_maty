defmodule Maty.Typechecker.Error.FrameworkUsage do
  def missing_session_registration(module) do
    """
    \n\n** (ElixirMatyTypeError) Framework Usage Violation: Missing Session Registration
      Module: #{module}
      --
      Actor does not register in a session in the on_link/2 callback
    """
  end

  def invalid_init_handler(module, line: line) do
    """
    \n\n** (ElixirMatyTypeError) Framework Usage Violation: Invalid Initialisation handler
      Module: #{module}
      Line: #{line}
      --
      Actor tries to register with invalid initialisation handler
    """
  end

  def use_of_native_communication(module, [{:line, line} | _], op: op) do
    comm_op =
      case op do
        :send -> "send/2"
        :receive -> "receive block"
      end

    """
    \n\n** (ElixirMatyTypeError) Framework Usage Violation: Attempted Native Communication
      Module: #{module}
      Line: #{line}
      --
      Actor attempted communication using #{comm_op}
    """
  end
end
