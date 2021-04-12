(* Kind *)

module Kind = struct

  type t =
    | Var
    | Constr
    | Arrow
    | Tuple
    | Other

  let to_int = function
    | Var -> 0
    | Constr -> 1
    | Arrow -> 2
    | Tuple -> 3
    | Other -> 4

  let of_int = function
    | 0 -> Var
    | 1 -> Constr
    | 2 -> Arrow
    | 3 -> Tuple
    | 4 -> Other
    | _ -> assert false

  let to_string = function
    | Var -> "variable"
    | Constr -> "constructor"
    | Arrow -> "arrow"
    | Tuple -> "tuple"
    | Other -> "other"

  let pp fmt t =
    Fmt.string fmt @@ to_string t

end

(* Base *)

module rec Base : sig

  type t =
    | Var of Variable.t
    | Constr of LongIdent.t * t Array.t
    | Arrow of Set.t * t
    | Tuple of Set.t
    | Other of Int.t

  val kind : t -> Kind.t

  val compare : t -> t -> Int.t
  val equal : t -> t -> Bool.t

end = struct

  type t =
    | Var of Variable.t
    | Constr of LongIdent.t * t Array.t
    | Arrow of Set.t * t
    | Tuple of Set.t
    | Other of Int.t

  let kind = function
    | Var _ -> Kind.Var
    | Constr _ -> Kind.Constr
    | Arrow _ -> Kind.Arrow
    | Tuple _ -> Kind.Tuple
    | Other _ -> Kind.Other

  let to_int t =
    Kind.to_int @@ kind t

  let rec compare t1 t2 =
      if t1 == t2 then 0
      else
        let (<?>) = CCOrd.(<?>) in
        match t1, t2 with
        | Var t1, Var t2 ->
            Variable.compare t1 t2
        | Constr (lid1, args1), Constr (lid2, args2) ->
            LongIdent.compare lid1 lid2
            <?> (CCArray.compare compare, args1, args2)
        | Arrow (arg1, ret1), Arrow (arg2, ret2) ->
            compare ret1 ret2
            <?> (Set.compare, arg1, arg2)
        | Tuple t1, Tuple t2 ->
            Set.compare t1 t2
        | Other t1, Other t2 ->
            CCInt.compare t1 t2
        | _ ->
            CCInt.compare (to_int t1) (to_int t2)

  let equal t1 t2 =
    compare t1 t2 = 0

end

(* Set *)

and Set : sig

  type elt = Base.t
  type t

  val compare : t -> t -> Int.t

  val of_list : elt List.t -> t
  val of_iter : elt Iter.t -> t
  val to_iter : t -> elt Iter.t
  val as_array : t -> elt Array.t

  val empty : t
  val is_empty : t -> Bool.t
  val length : t -> Int.t
  val singleton : elt -> t
  val union : t -> t -> t
  val add : elt -> t -> t
  val fold : (elt -> 'a -> 'a) -> t -> 'a -> 'a
  val map : (elt -> elt) -> t -> t
  val min_elt : t -> elt

  val pp : elt Fmt.t -> t Fmt.t

end = struct

  type elt = Base.t
  type t = elt Array.t

  let compare = CCArray.compare Base.compare
  let sort = CCArray.sort Base.compare

  let of_list lst =
    let t = CCArray.of_list lst in
    sort t ;
    t

  let of_iter it =
    let t = Iter.to_array it in
    sort t ;
    t

  let to_iter = Iter.of_array

  let as_array = CCFun.id

  let empty = [||]
  let is_empty t = t = [||]

  let length = CCArray.length

  let singleton elt = [| elt |]

  let union t1 t2 =
    let t = CCArray.append t1 t2 in
    sort t ;
    t

  let add elt t =
    union (singleton elt) t

  let fold fn t acc =
    CCArray.fold_left (CCFun.flip fn) acc t

  let map fn t =
    of_iter @@ Iter.map fn @@ to_iter t

  let min_elt t = t.(0)

  let pp pp_elt fmt = function
    | [||] ->
        Fmt.string fmt "()"
    | [| elt |] ->
        pp_elt fmt elt
    | t ->
        Fmt.pf fmt "(@ %a@ )"
          Fmt.(array ~sep:(any ", ") pp_elt) t

end

include Base

(* Hashcons *)

module Hashcons = struct

  type elt = {
    node : t ;
    mutable tag : Int.t ;
  }

  module Set = Weak.Make (struct
    type t = elt
    let equal lhs rhs = compare lhs.node rhs.node = 0
    let hash self = CCHash.poly self.node
  end)

  type t = {
    tbl : Set.t ;
    mutable elt_cnt : Int.t ;
  }

  let make sz = {
    tbl = Set.create sz ;
    elt_cnt = 0 ;
  }

  let hashcons t ty =
    let elt = { node = ty ; tag = -1 } in
    let elt' = Set.merge t.tbl elt in
    if elt == elt' then begin
      elt.tag <- t.elt_cnt ;
      t.elt_cnt <- t.elt_cnt + 1
    end ;
    elt'.node

end

(* Env *)

module Env = struct

  type t = {
    var_gen : Variable.Gen.t ;
    var_names : String.t Variable.HMap.t ;
    hcons : Hashcons.t ;
  }

  let make ?(var_gen = Variable.Gen.make 10) ?(var_names = Variable.HMap.create 17) () = {
    var_gen ;
    var_names ;
    hcons = Hashcons.make 17 ;
  }

end

(* importation functions *)

let make_var (env : Env.t) =
  let module StringHMap = CCHashtbl.Make (CCString) in
  let vars = StringHMap.create 17 in
  function
    | None ->
        Var (Variable.Gen.gen env.var_gen)
    | Some name ->
        match StringHMap.get vars name with
        | Some t -> t
        | None ->
            let var = Variable.Gen.gen env.var_gen in
            let t = Var var in
            Variable.HMap.add env.var_names var name ;
            StringHMap.add vars name t ;
            t

let make_constr lid = function
  | [||] when lid = LongIdent.unit -> Tuple Set.empty
  | args -> Constr (lid, args)

let make_arrow arg ret =
  match arg, ret with
  | Tuple tpl, _ when Set.is_empty tpl ->
      ret
  | Tuple tpl, Arrow (args, ret) ->
      Arrow (Set.union tpl args, ret)
  | _, Arrow (args, ret) ->
      Arrow (Set.add arg args, ret)
  | Tuple tpl, _ ->
      Arrow (tpl, ret)
  | _, _ ->
      Arrow (Set.singleton arg, ret)

let make_tuple elts =
  let aux = function
    | Tuple elts -> elts
    | elt -> Set.singleton elt
  in
  let elts = Set.fold (fun elt -> Set.union @@ aux elt) elts Set.empty in
  if Set.length elts = 1 then
    Set.min_elt elts
  else Tuple elts

let make_other x =
  Other (CCHash.poly x)

let of_outcometree of_outcometree make_var (out_ty : Outcometree.out_type) =
  match out_ty with
  | Otyp_var (_, name) ->
      make_var @@ Some name
  | Otyp_constr (id, args) ->
      args
      |> Iter.of_list
      |> Iter.map of_outcometree
      |> Iter.to_array
      |> make_constr (LongIdent.of_outcometree id)
  | Otyp_arrow (_, arg, ret) ->
      make_arrow (of_outcometree arg) (of_outcometree ret)
  | Otyp_tuple elts ->
      elts
      |> Iter.of_list
      |> Iter.map of_outcometree
      |> Set.of_iter
      |> make_tuple
  | Otyp_alias (out_ty, _) ->
      of_outcometree out_ty
  (* not handled *)
  | Otyp_object _
  | Otyp_class _
  | Otyp_variant _
  | Otyp_module _
  | Otyp_attribute _
  (* not simple types *)
  | Otyp_stuff _
  | Otyp_poly _
  | Otyp_abstract
  | Otyp_open
  | Otyp_manifest _
  | Otyp_record _
  | Otyp_sum _ ->
      make_other out_ty

let of_parsetree of_parsetree make_var (parse_ty : Parsetree.core_type) =
  match parse_ty.ptyp_desc with
  | Ptyp_any ->
      make_var None
  | Ptyp_var name ->
      make_var @@ Some name
  | Ptyp_constr (id, args) ->
      args
      |> Iter.of_list
      |> Iter.map of_parsetree
      |> Iter.to_array
      |> make_constr id.txt
  | Ptyp_arrow (_, arg, ret) ->
      make_arrow (of_parsetree arg) (of_parsetree ret)
  | Ptyp_tuple elts ->
      elts
      |> Iter.of_list
      |> Iter.map of_parsetree
      |> Set.of_iter
      |> make_tuple
  | Ptyp_alias (parse_ty, _)
  | Ptyp_poly (_, parse_ty) ->
      of_parsetree parse_ty
  (* not handled *)
  | Ptyp_object _
  | Ptyp_class _
  | Ptyp_variant _
  | Ptyp_package _
  | Ptyp_extension _ ->
      make_other parse_ty

let wrap fn (env : Env.t) x =
  let make_var = make_var env in
  let rec fn' x =
    x
    |> fn fn' make_var
    |> Hashcons.hashcons env.hcons
  in
  fn' x

let of_outcometree = wrap of_outcometree
let of_parsetree = wrap of_parsetree

let of_lexing env lexbuf =
  lexbuf
  |> Parse.core_type
  |> of_parsetree env

let of_string env str =
  str
  |> Lexing.from_string
  |> of_lexing env

(* utility functions *)

let head = function
  | Arrow (_, ret) -> ret
  | t -> t

let tail = function
  | Arrow (args, _) -> args
  | _ -> Set.empty

let rec substitute sub =
  let substitute t = substitute sub t in
  let substitute_set = Set.map substitute in
  fun t ->
    match t with
    | Var var ->
        begin match Variable.Map.find_opt var sub with
          | None -> t
          | Some t -> t
        end
    | Constr (lid, args) ->
        make_constr lid @@ CCArray.map substitute args
    | Arrow (args, ret) ->
        make_arrow (make_tuple @@ substitute_set args) (substitute ret)
    | Tuple elts ->
        make_tuple @@ substitute_set elts
    | Other _ ->
        t

let rec vars t k =
  match t with
  | Other _ ->
      ()
  | Var var ->
      k var
  | Constr (_, args) ->
      CCArray.iter (fun t -> vars t k) args
  | Tuple elts ->
      Iter.flat_map vars (Set.to_iter elts) k
  | Arrow (args, ret) ->
      Iter.flat_map vars (Set.to_iter args) k ;
      vars ret k

(* several notions of size *)

module Size = struct

  type kind =
    | VarCount
    | NodeCount
    | HeadKind
    | TailRootVarCount
    | RootVarCount
    | TailLength

  type t = Int.t

  let pp kind fmt t =
    match kind with
    | HeadKind -> Kind.(pp fmt @@ of_int t)
    | _ -> Fmt.int fmt t

  module Map = CCMap.Make (CCInt)
  module HMap = CCHashtbl.Make (CCInt)

end

let rec size (sz_kind : Size.kind) t =
  match sz_kind with
  | VarCount ->
      Variable.Set.(cardinal @@ of_iter @@ vars t)
  | NodeCount ->
      let rec aux = function
        | Var _ | Other _ ->
            1
        | Constr (_, args) ->
            1 + CCArray.fold (fun acc t -> acc + aux t) 0 args
        | Arrow (args, ret) ->
            1 + aux_set args + aux ret
        | Tuple elts ->
            1 + aux_set elts
      and aux_set set =
        Set.fold (fun t acc -> aux t + acc) set 0
      in
      aux t
  | HeadKind ->
      Kind.to_int @@ kind @@ head t
  | TailRootVarCount ->
      let aux t =
        (+) @@ CCBool.to_int @@ (kind t = Kind.Var)
      in
      Set.fold aux (tail t) 0
  | RootVarCount ->
      let sz = size Size.TailRootVarCount t in
      let hd_kind = kind @@ head t in
      sz + (CCBool.to_int @@ (hd_kind = Kind.Var))
  | TailLength ->
      Set.length @@ tail t

(* pretty printing *)

let pp_array pp_elt fmt = function
  | [||] ->
      Fmt.string fmt "()"
  | [| elt |] ->
      pp_elt fmt elt
  | arr ->
      Fmt.pf fmt "@[<2>(%a)@]"
        Fmt.(array ~sep:(any ", ") pp_elt) arr

let rec pp var_names =
  let pp fmt = pp var_names fmt in
  fun fmt -> function
    | Var var ->
        Variable.pp var_names fmt var
    | Constr (lid, [||]) ->
        LongIdent.pp fmt lid
    | Constr (lid, args) ->
        Fmt.pf fmt "%a@ %a"
          (pp_array pp) args
          LongIdent.pp lid
    | Arrow (args, ret) ->
        Fmt.pf fmt "@[<2>%a@ ->@ %a@]"
          (Set.pp pp) args
          pp ret
    | Tuple elts ->
        Fmt.pf fmt "@[<2>%a@]"
          (Set.pp pp) elts
    | Other _ ->
        Fmt.string fmt "_"
