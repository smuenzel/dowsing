(** Pure subterms: Variables or constants *)

type t =
  | Var of Variable.t
  | Constant of LongIdent.t

let dummy = Constant (Longident.Lident "dummy")
let var x = Var x
let constant p = Constant p

let pp ppf = function
  | Var i -> Variable.pp ppf i
  | Constant p -> LongIdent.pp ppf p

let as_typexpr (env : Type.Env.t) = function
  | Var v -> Type.var env v
  | Constant c -> Type.constr env c [||]
