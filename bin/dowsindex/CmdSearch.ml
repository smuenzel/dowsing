open Common

type opts = {
  copts : copts ;
  exhaustive : Bool.t ;
  cnt : Int.t Option.t ;
  idx_file : Fpath.t ;
  ty : Type.t ;
  pkgs : String.t List.t ;
}

let main opts =
  let module Indexing = Index in
  let module Index = (val opts.copts.idx) in
  let pkgs =
    if CCList.is_empty opts.pkgs
    then None
    else Some opts.pkgs
  in
  let idx =
    try
      Index.load opts.idx_file
    with Sys_error _ ->
      error @@ Fmt.str "cannot open index file `%a'"
        Fpath.pp opts.idx_file
  in
  let res =
    let find =
      if opts.exhaustive
      then Index.find
      else Index.find_with
    in
    let iter_idx =
      try find idx env_query opts.ty ?pkgs
      with Not_found -> error "unknown package"
    in
    iter_idx
    |> Iter.sort ~cmp:(fun (ty1, _, unif1) (ty2, _, unif2) ->
      CCOrd.(Subst.compare unif1 unif2
        <?> (Type.compare, ty1, ty2))
    )
    |> Iter.flat_map (fun (_, cell, _) ->
      Indexing.Cell.iter cell
    )
  in
  let res = CCOption.fold (CCFun.flip Iter.take) res opts.cnt in
  Fmt.pr "@[<v>%a@]@."
    (Fmt.iter Iter.iter Indexing.Info.pp) res

let main copts exhaustive cnt idx_file ty pkgs =
  try Ok (main { copts ; exhaustive ; cnt ; idx_file ; ty ; pkgs })
  with Error msg -> Error (`Msg msg)

open Cmdliner
open Cmd

let exhaustive =
  let doc = "Use exhaustive search (slow)." in
  Arg.(value & flag & info [ "exhaustive" ] ~doc)

let cnt =
  let docv = "n" in
  let doc = "Report only the first $(docv) results." in
  Arg.(value & opt (some int) None & info [ "n" ] ~docv ~doc)

let idx_file =
  let docv = "file" in
  let doc = "Set index file." in
  Arg.(value & opt Convs.file Paths.idx_file & info [ "index" ] ~docv ~doc)

let ty =
  let docv = "type" in
  Arg.(required &
       pos ~rev:true 0 (some @@ Convs.scheme env_query) None & info [] ~docv)

let pkgs =
  let docv = "package" in
  Arg.(value & pos_left ~rev:true 0 string [] & info [] ~docv)

let cmd =
  let doc = "search index" in
  Cmd.v
    (info "search" ~sdocs:Manpage.s_common_options ~doc)
    Term.(term_result (const main $ copts $ exhaustive $ cnt $ idx_file $ ty $ pkgs))
  
