#import "@preview/simplebnf:0.2.0": *

= Core Calculus


#let ty(x) = math.sans(x)
#let kw(x) = math.bold(math.sans(x))

#let ty_handler = $ty("Handler")(S^?, A_L)$
#let ty_init = $ty("Init")(S, A, A_L)$

We use $x, y$ for variables, $c$ for constants, $f$ for function names, $h$ for handler names, $m$ for module names, $p, q$ for roles and $ell$ for labels. Each function name has a fixed arity, and we write $f$ for $f slash n$.

Top-level names are qualified by their module. Inside module $m$, a bare $f$ or $h$ abbreviates $m.f$ or $m.h$, and a handler name may only be referenced from its own module.

#bnf(
  Prod($C$, annot: [Base types], {
      Or[$ty("Bool") | ty("Number") | ty("Binary") | ty("Atom") | ty("Nil") | ty("Pid")$][] // do I also need Unit?
  }),
  Prod($A, B$, annot: [Types], {
    Or[$C$][base]
    Or[$[A]$][list]
    Or[$A_1 times ... times A_n$][tuple, $n >= 0$]
    Or[${ell_1 : A_1, ..., ell_n : A_n}$][record, $n >= 1$]
    Or[${C arrow.r.bar A}$][dictionary]
    Or[$(A_1, ..., A_n) arrow.r B$][function, $n >= 0$]
    Or[#ty_handler][message handler]
    Or[#ty_init][init handler]
    Or[$ty("AP"){p_i arrow.r.bar S_i}_(i in I)$][access point]
  }),
  Prod($S$, annot: [Session types], {
    Or[$S^! | S^?$][]
    Or[$h$][handler]
    Or[$ty("end")$][]
  }),
  Prod($S^!$, annot: [Send types], {
    Or[$p plus.o {ell_i (A_i) . S_i}_(i in I)$][]
  }),
  Prod($S^?$, annot: [Receive types], {
    Or[$p amp {ell_i (A_i) . S_i}_(i in I)$][]
  }),
  Prod($Gamma$, annot: [Environments], {
    Or[$dot$][]
    Or[$Gamma, x : A$][]
  }),
  Prod($Sigma$, annot: [Signatures], {
    Or[$dot$][]
    Or[$Sigma, m.f : arrow(A) arrow.r B$][function]
    Or[$Sigma, m.h : #ty_handler$][message handler]
    Or[$Sigma, m.h : #ty_init$][init handler]
    Or[$Sigma, m.kw("on_start") : arrow(A) arrow.r A_G$][start callback]
  }),
)

#bnf(
  Prod($"Mod"$, annot: [Modules], {
    Or[$kw("module") m thick chevron.l O, arrow(D) chevron.r$][]
  }),
  Prod($O$, annot: [Start callback], {
    Or[$kw("on_start") : arrow(A) arrow.r A_G thick chevron.l arrow(P)_i arrow.r M_i chevron.r_(i in I)$][]
  }),
  Prod($D$, annot: [Definitions], {
    Or[$kw("def") f : arrow(A) arrow.r B thick chevron.l arrow(P)_i arrow.r M_i chevron.r_(i in I)$][function]
    Or[$kw("handler") h : #ty_handler thick chevron.l ell_i thick arrow(K)_i chevron.r_(i in I)$][message handler]
    Or[$kw("init") h : #ty_init thick chevron.l arrow(K) chevron.r$][init handler]
  }),
  Prod($K$, annot: [Handler clauses], {
    Or[$P, P_L, P_G arrow.r M$][]
  }),
  Prod($U, V, W$, annot: [Values], {
    Or[$x | c | f | h$][]
    Or[$(V_1, ..., V_n)$][tuple]
    Or[$[] | [V | W]$][list]
    Or[${ell_1 = V_1, ..., ell_n = V_n}$][record, $n >= 1$]
    Or[${V_1 arrow.r.bar W_1, ..., V_n arrow.r.bar W_n}$][dictionary, $n >= 0$]
    Or[$lambda (x_1, ..., x_n). M$][abstraction]
    Or[$(V : A)$][annotation]
  }),
  Prod($P, Q$, annot: [Patterns], {
    Or[$x | "_" | c$][]
    Or[$(P_1, ..., P_n)$][tuple]
    Or[$[] | [P | Q]$][list]
    Or[${ell_1 = P_1, ..., ell_n = P_n}$][record, $n >= 1$]
    Or[${c_1 arrow.r.bar P_1, ..., c_n arrow.r.bar P_n}$][dictionary, $n >= 1$]
  }),
  Prod($M, N$, annot: [Computations], {
    Or[$kw("return") V$][return]
    Or[$V diamond.stroked.small W | diamond.stroked.small V$][operators]
    Or[$V(W_1, ..., W_n)$][application]
    Or[$kw("let") P = M kw("in") N$][binding]
    Or[$kw("case") V thick chevron.l P_i arrow.r M_i chevron.r_(i in I)$][branching]
    Or[$V.ell | {V | ell = W}$][field access, update]
    Or[$V[W] | {V | W arrow.r.bar U} | V without W$][lookup, insert, delete]
    Or[$p thick ! thick ell(V)$][send]
    Or[$kw("suspend") V thick W | kw("done") V$][suspend, done]
    Or[$kw("newAP"){p_i arrow.r.bar S_i}_(i in I)$][new access point]
    Or[$kw("register") V thick p thick W thick U$][register]
    Or[$kw("start") m thick arrow(V)$][start actor]
    Or[$(M : A)$][annotation]
  }),
)

// Throughout, we fix a global signature $Sigma$ and a current module $m$, whose global state type $A_G$ is given by $Sigma(m."on_start")$.

= Typing Rules

#import "@preview/curryst:0.6.0": rule, prooftree, rule-set

// Modes
#let syn = $arrow.r.double$
#let chk = $arrow.l.double$

// Judgements
#let vty(G, V, J) = $#G tack.r #V #J$
#let cty(G, T, M, J, T2) = $#G | #T triangle.r #M #J triangle.l #T2$
#let pty(P, A, D) = $tack.r #P arrow.l.double #A tack.l #D$
#let dty(D) = $tack.r #D$

// Scaffolding
#let blank = text(fill: gray)[?]
#let scaffold(name, conclusion) = prooftree(rule(name: [#name], blank, conclusion))

=== Values

#rule-set(
  prooftree(rule(name: [TV-Const], [c has base type C], vty($Gamma$, $c$, $syn C$))),
  prooftree(rule(name: [TV-Var], [$x : A in Gamma$], vty($Gamma$, $x$, $syn A$))),
  prooftree(rule(name: [TV-Fun], [$f : arrow(A) arrow.r B in Sigma$], vty($Gamma$, $f$, $syn arrow(A) arrow.r B$))),
  prooftree(rule(name: [TV-InitHandler], [$h : #ty_init in Sigma$], vty($Gamma$, $h$, $syn #ty_init$))),
  prooftree(rule(name: [TV-MessageHandler], [$h : #ty_handler in Sigma$], vty($Gamma$, $h$, $syn #ty_handler$))),
  prooftree(rule(name: [TV-Tuple-Syn], vty($Gamma$, $V_i$, $syn A_i$), [$i in 1..n$], vty($Gamma$, $(V_1, ..., V_n)$, $syn A_1 times ... times A_n$))),
  prooftree(rule(name: [TV-Tuple-Chk], vty($Gamma$, $V_i$, $chk A_i$), [$i in 1..n$], vty($Gamma$, $(V_1, ..., V_n)$, $chk A_1 times ... times A_n$))),
  prooftree(rule(name: [TV-Nil], [/* I don't think anything really goes here */], vty($Gamma$, [$[]$], $chk [A]$))),
  prooftree(rule(name: [TV-Cons-Syn], vty($Gamma$, $V$, $syn A$), vty($Gamma$, $W$, $chk [A]$), vty($Gamma$, $[V | W]$, $syn [A]$))),
  prooftree(rule(name: [TV-Cons-Chk], vty($Gamma$, $V$, $chk A$), vty($Gamma$, $W$, $chk [A]$), vty($Gamma$, $[V | W]$, $chk [A]$))),
  prooftree(rule(name: [TV-Record-Syn], vty($Gamma$, $V_i$, $syn A_i$), $i in 1..n$, vty($Gamma$, ${ell_1 = V_1, ..., ell_n = V_n}$, $syn {ell_1: A_1, ..., ell_n : A_n}$ ))),
  prooftree(rule(name: [TV-Record-Chk], vty($Gamma$, $V_i$, $chk A_i$), $i in 1..n$, vty($Gamma$, ${ell_1 = V_1, ..., ell_n = V_n}$, $chk {ell_1: A_1, ..., ell_n : A_n}$ ))),
  prooftree(rule(name: [TV-Dict-Syn], vty($Gamma$, $V_1$, $syn A$), vty($Gamma$, $W_1$, $syn B$), vty($Gamma$, $V_i$, $chk A$), vty($Gamma$, $W_i$, $chk B$), $i in 2..n$, vty($Gamma$, ${V_1 arrow.r.bar W_1, ..., V_n arrow.r.bar W_n}$, $syn {A arrow.r.bar B}$))),
  prooftree(rule(name: [TV-Dict-Chk], vty($Gamma$, $V_i$, $chk A$), vty($Gamma$, $W_i$, $chk B$), $i in 1..n$, vty($Gamma$, ${V_1 arrow.r.bar W_1, ..., V_n arrow.r.bar W_n}$, $chk {A arrow.r.bar B}$))),
  // not sure how to nicely extend the environment Gamma with the types of each argument
  // also not sure if the expression M is checked or synthesized
  prooftree(rule(name: [TV-Abs], vty($Gamma, (x_i : A_i)_(i in 1..n)$, $M$, $chk B$), vty($Gamma$, $lambda (x_1, ..., x_n).M$, $chk (A_1, ..., A_n) arrow.r B$))),
  // fix overflow here
  prooftree(rule(name: [TV-Ann], vty($Gamma$, $V$, $chk A$), vty($Gamma$, $(V : A)$, $syn A$))),
  prooftree(rule(name: [TV-Switch], vty($Gamma$, $V$, $syn A$), vty($Gamma$, $V$, $chk A$))),
)

=== Computations

#rule-set(
  scaffold("T-Return", cty($Gamma$, $T$, $kw("return") V$, blank, blank)),
  scaffold("T-UnOp", cty($Gamma$, $T$, $diamond.stroked.small V$, blank, blank)),
  scaffold("T-BinOp", cty($Gamma$, $T$, $V diamond.stroked.small W$, blank, blank)),
  scaffold("T-Cmp", cty($Gamma$, $T$, $V diamond.stroked.small W$, blank, blank)),
  scaffold("T-App", cty($Gamma$, $T$, $V(W_1, ..., W_n)$, blank, blank)),
  scaffold("T-Let-Syn", cty($Gamma$, $T$, $kw("let") P = M kw("in") N$, blank, blank)),
  scaffold("T-Let-Chk", cty($Gamma$, $T$, $kw("let") P = M kw("in") N$, blank, blank)),
  scaffold("T-Case-Syn", cty($Gamma$, $T$, $kw("case") V thick chevron.l P_i arrow.r M_i chevron.r_(i in I)$, blank, blank)),
  scaffold("T-Case-Chk", cty($Gamma$, $T$, $kw("case") V thick chevron.l P_i arrow.r M_i chevron.r_(i in I)$, blank, blank)),
  scaffold("T-Field", cty($Gamma$, $T$, $V.ell$, blank, blank)),
  scaffold("T-Update", cty($Gamma$, $T$, ${V | ell = W}$, blank, blank)),
  scaffold("T-Lookup", cty($Gamma$, $T$, $V[W]$, blank, blank)),
  scaffold("T-Insert", cty($Gamma$, $T$, ${V | W arrow.r.bar U}$, blank, blank)),
  scaffold("T-Delete", cty($Gamma$, $T$, $V without W$, blank, blank)),
  scaffold("T-Send", cty($Gamma$, blank, $p thick ! thick ell(V)$, blank, blank)),
  scaffold("T-Suspend", cty($Gamma$, blank, $kw("suspend") V thick W$, blank, blank)),
  scaffold("T-Done", cty($Gamma$, blank, $kw("done") V$, blank, blank)),
  scaffold("T-NewAP", cty($Gamma$, $T$, $kw("newAP"){p_i arrow.r.bar S_i}_(i in I)$, blank, blank)),
  scaffold("T-Register", cty($Gamma$, $T$, $kw("register") V thick p thick W thick U$, blank, blank)),
  scaffold("T-Start", cty($Gamma$, $T$, $kw("start") m thick arrow(V)$, blank, blank)),
  scaffold("T-Ann", cty($Gamma$, $T$, $(M : A)$, blank, blank)),
  scaffold("T-Switch", cty($Gamma$, $T$, $M$, blank, blank)),
)

=== Patterns

#rule-set(
  scaffold("TP-Var", pty($x$, blank, blank)),
  scaffold("TP-Wild", pty($"_"$, blank, blank)),
  scaffold("TP-Const", pty($c$, blank, blank)),
  scaffold("TP-Tuple", pty($(P_1, ..., P_n)$, blank, blank)),
  scaffold("TP-Nil", pty($[]$, blank, blank)),
  scaffold("TP-Cons", pty($[P | Q]$, blank, blank)),
  scaffold("TP-Record", pty(${ell_1 = P_1, ..., ell_n = P_n}$, blank, blank)),
  scaffold("TP-Dict", pty(${c_1 arrow.r.bar P_1, ..., c_n arrow.r.bar P_n}$, blank, blank)),
)

=== Definitions

#rule-set(
  scaffold("TD-Def", dty($kw("def") f : arrow(A) arrow.r B thick chevron.l arrow(P)_i arrow.r M_i chevron.r_(i in I)$)),
  scaffold("TD-Handler", dty($kw("handler") h : #ty_handler thick chevron.l ell_i thick arrow(K)_i chevron.r_(i in I)$)),
  scaffold("TD-Init", dty($kw("init") h : #ty_init thick chevron.l arrow(K) chevron.r$)),
  scaffold("TD-Clause", blank),
  scaffold("TD-OnStart", dty($kw("on_start") : arrow(A) arrow.r A_G thick chevron.l arrow(P)_i arrow.r M_i chevron.r_(i in I)$)),
  scaffold("TD-Module", dty($kw("module") m thick chevron.l O, arrow(D) chevron.r$)),
  scaffold("TD-Program", dty($arrow("Mod")$)),
)
