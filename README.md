# Elixir-Maty

A tool for statically checking Elixir communication patterns. Multiparty Session Typing (MPST) for Elixir apps using the Maty language design

## tl;dr

- BYOP (bring your own (verified MPST) Protocol)
- you write actors. an actor plays some role(s) in the protocol
- each actor is a module. all communication happens in handlers
- every handler has a session type
- actors have two kinds of state: global state per actor, local state per role
- the typechecker runs at compile time
- if an actor does not follow its session type, compilation fails

## Run the examples

```
# fetch deps
mix deps.get

# run each example
mix two_buyer
mix stash_queue
```

- `examples/two_buyer`: two buyers, one seller. buyers split the price of a book.
- `examples/stash_queue`: messages arrive in wrong order. runtime keeps them until the session type wants them.

## Tests

```
mix test
```

## More

- `docs/v2.typ`: the calculus and the typing rules.
