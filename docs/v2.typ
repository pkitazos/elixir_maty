= Core Calculus

#let qquad = $quad quad$

We use $x, y$ for variables, $c$ for constants, $f$ for function names, $h$ for handler names, $m$ for module names, $p, q$ for roles and $ell$ for labels. Each function name has a fixed arity, and we write $f$ for $f slash n$.

$
  "Base types" qquad C &::= "boolean" | "number" | "binary" | "atom" | "nil" \

  "Types" qquad A, B &::= C | "Pid" | [A] | A_1 times ... times A_n quad (n >= 0) \
    &| {ell_1 : A_1, ..., ell_n : A_n} quad (n >= 1) | {C arrow.r.bar A} \
    &| (A_1, ..., A_n) arrow.r B quad (n >= 0) \
    &| "Handler"^("msg")[S^?, A_L, A_G] | "Handler"^("init")[S, A, A_L, A_G] \
    &| "AP"{p_i arrow.r.bar S_i}_(i in I) \
\ \
  "Session types" qquad S &::= S^! | S^? | h | "end" \
  "Send types" qquad S^! &::= p plus.o {ell_i (A_i) . S_i}_(i in I) \
  "Receive types" qquad S^? &::= p amp {ell_i (A_i) . S_i}_(i in I) \
\ \
  "Environments" qquad Gamma &::= dot | Gamma, x : A \
  "Signatures" qquad Sigma &::= dot | Sigma, f : arrow(A) arrow.r B \
    &| Sigma, h : "Handler"^("msg")[S^?, A_L, A_G] \
    &| Sigma, h : "Handler"^("init")[S, A, A_L, A_G]
$

$
  "Modules" qquad "Mod" &::= "module" m thick chevron.l arrow(D) chevron.r \
  "Definitions" qquad D &::= "def" f : arrow(A) arrow.r B thick chevron.l arrow(P)_i arrow.r M_i chevron.r_(i in I) \
    &| "handler" h : "Handler"^("msg")[S^?, A_L, A_G] thick chevron.l ell_i thick arrow(K)_i chevron.r_(i in I) \
    &| "init" h : "Handler"^("init")[S, A, A_L, A_G] thick chevron.l arrow(K) chevron.r \
  "Handler clauses" qquad K &::= P, sigma_L, sigma_G arrow.r M \
\ \
  "Values" qquad V, W &::= x | c | f | h | (V_1, ..., V_n) | [] | [V | W] \
    &| {ell_1 = V_1, ..., ell_n = V_n} quad (n >= 1) \
    &| {c_1 arrow.r.bar V_1, ..., c_n arrow.r.bar V_n} quad (n >= 0) \
    &| lambda (x_1, ..., x_n). M | (V : A) \
\ \
  "Patterns" qquad P, Q, sigma &::= x | "_" | c | (P_1, ..., P_n) | [] | [P | Q] \
    &| {ell_1 = P_1, ..., ell_n = P_n} quad (n >= 1) \
    &| {c_1 arrow.r.bar P_1, ..., c_n arrow.r.bar P_n} quad (n >= 1) \
\ \
  "Computations" qquad M, N &::= "return" V | V diamond.stroked.small W | diamond.stroked.small V | V(W_1, ..., W_n) \
    &| "let" P = M "in" N | "case" V thick chevron.l P_i arrow.r M_i chevron.r_(i in I) \
    &| V.ell | {V | ell = W} \
    &| V[W] | {V | W arrow.r.bar W'} | V without W \
    &| p thick ! thick ell(V) | "suspend" V thick W | "done" V \
    &| "newAP"{p_i arrow.r.bar S_i}_(i in I) | "register" V thick p thick W thick W' \
    &| "start" m thick arrow(V) \
    // optional: | (M : A), for a case in a synthesis position
\ \
  "Evaluation contexts" qquad E &::= [ ] | "let" P = E "in" N
$
