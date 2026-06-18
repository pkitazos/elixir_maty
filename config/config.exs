import Config

# MATY_DEBUG: "1" stack traces, "2" function signatures
flags = (System.get_env("MATY_DEBUG") || "") |> String.split(",", trim: true)

config :maty,
  debug_stack_trace: "1" in flags,
  debug_function_signatures: "2" in flags

config :logger, :default_formatter, format: "[$level] $message\n"
