/-- Short alias for fallible parsing -/
abbrev P (α : Type) := Except String α

def P.bindM [Monad m] (x : P α) (f : α → m (P β)) : m (P β) := do
  match x with
  | .ok a => f a
  | .error e => return .error e

def P.map (f : α → β) : P α → P β := Except.map f

def P.orElse (x : P α) (y : Unit → P α) : P α :=
  match x with | .ok a => .ok a | .error _ => y ()
