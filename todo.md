# todo

## Tasks

Go through every file and add a butt-load of comments essentially thinking out loud about each part of the codebase.
It's been a while since I wrote most of this and I remember some of it was a bit confused. Through this process I will hopefully get back into the right head pace to both, finish this project (or at least make a little more progress) and start my PhD work.

Visited so far:

- [x] [hook](./lib/maty/hook.ex)
- [x] [typechecker](./lib/maty/typechecker.ex)
- [x] [typechecker/preprocessor](./lib/maty/typechecker/preprocessor.ex)
- [x] [types](./lib/maty/types.ex)
- [x] [utils](./lib/maty/utils.ex)
- [x] [st/st](./lib/maty/st/st.ex)
- [x] [typechecker/delta](./lib/maty/typechecker/delta.ex)

All:

- [ ] [typechecker/type_spec_parser](./lib/maty/typechecker/type_spec_parser.ex)
- [ ] [typechecker/tc](./lib/maty/typechecker/tc.ex)
- [ ] [typechecker/helpers](./lib/maty/typechecker/helpers.ex)
- [ ] [typechecker/pattern_binding](./lib/maty/typechecker/pattern_binding.ex)

- [ ] [access_point](./lib/maty/access_point.ex)
- [ ] [actor](./lib/maty/actor.ex)

- [ ] [dsl/dsl](./lib/maty/dsl/dsl.ex)
- [ ] [dsl/handlers](./lib/maty/dsl/handlers.ex)
- [ ] [dsl/state](./lib/maty/dsl/state.ex)

- [ ] [parser/core](./lib/maty/parser/core.ex)
- [ ] [parser/parser](./lib/maty/parser/parser.ex)

- [ ] [typechecker/error/internal](./lib/maty/typechecker/error/internal.ex)
- [ ] [typechecker/error/framework_usage](./lib/maty/typechecker/error/framework_usage.ex)
- [ ] [typechecker/error/function_call](./lib/maty/typechecker/error/function_call.ex)
- [ ] [typechecker/error/pattern_matching](./lib/maty/typechecker/error/pattern_matching.ex)
- [ ] [typechecker/error/protocol_violation](./lib/maty/typechecker/error/protocol_violation.ex)
- [ ] [typechecker/error/type_mismatch](./lib/maty/typechecker/error/type_mismatch.ex)
- [ ] [typechecker/error/type_specification](./lib/maty/typechecker/error/type_specification.ex)

## tasks

- [ ] bind should only accept result (no 2-tuple) which means I gotta go fix whatever produces the 2-tuple errors or we have a proper lift?
- [ ] prune un-used bind combinators (assert_ok)
- [ ] proper map type support for actor state and destructuring in the DSL

## Questions

- How do I cut up a recursive session type? 

tl;dr - unfold once and inline
