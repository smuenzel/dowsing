module Signature = struct

  type t = {
    lid : LongIdent.t ;
  }

  let compare t1 t2 = LongIdent.compare_humans t1.lid t2.lid

  let pp fmt t = LongIdent.pp fmt t.lid

end

module Slot = struct

  include CCSet.Make (Signature)

  let prune sigs =
    let not_internal Signature.{ lid } =
      not @@ Iter.exists (CCString.mem ~start:0 ~sub:"__") @@ LongIdent.to_iter lid
    in
    let sigs' = filter not_internal sigs in
    if not @@ is_empty sigs' then sigs' else sigs

  let representative = min_elt

  let pp = Fmt.using representative Signature.pp

end

type t = Slot.t LongIdent.Map.t

let singleton lid s =
  LongIdent.Map.(add lid (Slot.singleton s) empty)

let add lid s t =
  t |> LongIdent.Map.update lid @@ fun sigs ->
    let sigs =
      match sigs with
      | None -> Slot.singleton s
      | Some sigs -> Slot.add s sigs
    in
    Some sigs

let update lid s = function
  | None -> singleton lid s
  | Some t -> add lid s t

let pp fmt info =
  LongIdent.Map.to_iter_values info
  |> Iter.map Slot.prune
  |> Iter.sort ~cmp:Slot.compare
  |> Fmt.pf fmt "@[<v>%a@]" (Fmt.iter ~sep:Fmt.sp Iter.iter Slot.pp)
