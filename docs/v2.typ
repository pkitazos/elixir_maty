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
