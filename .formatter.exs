# Used by "mix format"
[
  inputs: ["mix.exs", "config/**/*.exs", "lib/**/*.ex", "test/**/*.{ex,exs}", "examples/**/*.ex"],
  locals_without_parens: [expect: 2, expect_st: 2, defhandler: 2, global_state: 1, local_state: 2],
]
