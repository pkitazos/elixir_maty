import Config

config :maty,
  debug_stack_trace: System.get_env("MATY_DEBUG") == "1"
