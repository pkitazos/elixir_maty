# todo

## Ongoing work

I seem to get burst of energy to work on this project every couple of months each lasting anywhere from a couple weeks to a couple months with several months in between. This unfortunately means that every time I come back to work on the project I have different ideas about what the right way to build this is (at one point I was very unit-test pilled which lead to the horrible test suite that exists right now, at another I was under the impression that this could be used as more than just a research prototype, right now for example I'm going through my "DSLs are actually good" phase).

All this to say, there are lots of bits in here that need to be tidied up, thrown out, or documented much more thoroughly. Below you can see how far along I got with each module, what's been done (imo well) and what needs re-doing.

- [ ] `Maty`
  Needs documentation

- [ ] `Maty.Application`
  As far as I can tell, doesn't do anything - can be deleted

- [ ] `Maty.AccessPoint`
  Needs documentation, but otherwise in good shape

- [ ] `Maty.Actor`
  Needs documentaiton, but otherwise in good shape

- [ ] `Maty.DSL`
  Needs documentation and a little cleanup
  - [ ] `Maty.DSL.Pattern`
    Needs a lot of work, this is one of three parsers in the project and I don't like how disconnected they all are

- [ ] `Maty.Hook`
  Can potentially be merged into Typechecker in some capacity

- [ ] `Maty.Protocol`
  Needs docs


- [ ] `Maty.Runtime`
  Needs docs, otherwise in good shape
  - [x] `Maty.Runtime.Envelope`
  - [ ] `Maty.Runtime.InternalState`
    Need to still figure out how to type actor state
  - [ ] `Maty.Runtime.Session`
    Also need to figure out how to type actor state here

  
- [ ] `Maty.ST`
  Can potentially replace the repr with String.Chars protoco
  - [x] `Maty.ST.SBottom`


- [ ] `Maty.Typechecker`
  Needs a lot of work, some bits in here feel like they belong to Hook
  - [ ] `Maty.Typechecker.Ctx`
    Need to rename some of the fields I think
  - [ ] `Maty.Typechecker.Delta`
    Bad, Terrible, what was I thinking

  - [ ] `Maty.Typechecker.Error`
    Good, but needs more documentation (like in a markdown file explaining the error variants).
    Almost all the variants below are missing better documentation / examples
    - [ ] `Maty.Typechecker.Error.Cause`
      This is fine, but might not be necessary after the refactor
    - [ ] `Maty.Typechecker.Error.Formatter`
      This is fine for now, but eventually would be nice to be able to give nicer errors (like Elixir compiler)
    - [ ] `Maty.Typechecker.Error.FrameworkUsage`
    - [ ] `Maty.Typechecker.Error.FunctionCall`
    - [ ] `Maty.Typechecker.Error.NameResolution`
    - [ ] `Maty.Typechecker.Error.PatternMatching`
    - [ ] `Maty.Typechecker.Error.ProtocolViolation`
    - [ ] `Maty.Typechecker.Error.TypeMismatch`
    - [ ] `Maty.Typechecker.Error.TypeSpecification`

  - [ ] `Maty.Typechecker.Helpers`
    Still a big mess, need to see if I can move stuff around or standardise more APIs
    though tbf while working on the updated `Check` monad, it seems like we have 3/4 variants that we need to support
    - a boolean check `true | false`
    - a fetch `{:ok, val} | :error`
    - a check `:ok | {:error, e}`
    - a normal result `{:ok, val} | {:error, e}`

  - [x] `Maty.Typechecker.Judgment`
    Okay, but needs to be merged into the new `Check` monad
  - [ ] `Maty.Typechecker.PatternBinding`
    Idk about this one, feels a bit underbaked

  - [ ] `Maty.Typechecker.Preprocessor`
    Also needs a bit more tlc

  - [ ] `Maty.Typechecker.TC`
    Okay for the most part, obviously it's incomplete (map support is only half-done) and the new `Check` monad isn't used. It should hopefully make the rules nicer to read
    - [x] `Maty.Typechecker.TC.Bind`
      This was a good first idea I think, but my execution wasn't great. Needs to be merged into the new `Check` monad also
    - [ ] `Maty.Typechecker.TC.IO`
      I don't like this, but it's just for demo purposes
    - [x] `Maty.Typechecker.TC.Thread`
      Needs to be merged into `Check` monad
    - [ ] `Maty.Typechecker.TC.Timer`
      Also just for demo purposes - consider unchecked block
    - [ ] `Maty.Typechecker.TC.WF`
      Could use some tlc (and potentially the `Check` monad)
    
  - [ ] `Maty.Typechecker.TypeSpecParser`
    Yet _another_ parser! I don't like that I have so many and they're all half-baked


- [ ] `Maty.Types`
  Fine, almost good even
  - [ ] `Maty.Types.T`
    actively bad, I don't like that I need to do this (potentially I won't have to for much longer)


- [ ] `Maty.Utils`
  Bad
  - [ ] `Maty.Utils.Env`
    _Really_ bad


## Questions

- How do I cut up a recursive session type? 

tl;dr - unfold once and inline. (see "Subtyping for session types in the pi calculus")
