module Key = LongIdent

type info = {
  key : Key.t ;
  ty : Type.t ;
}

module Tree = struct

  module T =
    Trie.Node (Feature.ByHead) (
      Trie.Node (Feature.TailLength) (
        Trie.Leaf))

  type 'a t = 'a T.t

  let mk_features env ty =
    let open Feature in
    (ByHead.compute env ty, (TailLength.compute env ty, ty))

  let get env t ty =
    let features = mk_features env ty in
    T.get env t features

  let import env it =
    Iter.fold (fun m info ->
      let features = mk_features env info.ty in
      T.add features info m
    ) T.empty it

end

type t = {
  env : Type.Env.t ;
  infos : info Tree.t ;
}

let get_env (t : t) = t.env
let get_infos (t : t) = t.infos
let get t = Tree.get (get_env t) (get_infos t)

let import env it = {
  env ;
  infos = Tree.import env it ;
}

let iter_libindex pkg_dirs env kk =
  pkg_dirs
  |> LibIndex.Misc.unique_subdirs
  |> LibIndex.load
  |> LibIndex.all
  |> List.iter (fun info ->
    match info.LibIndex.kind with
    | LibIndex.Value ->
        let [@warning "-8"] Outcometree.Osig_value out_ty = Option.get info.ty in
        let out_ty = out_ty.oval_type in
        let ty = Type.of_outcometree env out_ty in
        let key = Key.of_list @@ info.path @ [ info.name ] in
        kk { key ; ty }
    | _ -> ()
  )

let make pkg_dirs =
  let env = Type.Env.make () in
  let it = iter_libindex pkg_dirs env in
  import env it

let iter t fn = LIdHMap.iter fn @@ get_infos t

module Archive = struct

  let of_index = CCFun.id
  let to_index = CCFun.id

  let load file : t =
    CCIO.with_in file Marshal.from_channel

  let save (t : t) file =
    CCIO.with_out file @@ fun out -> Marshal.to_channel out t []

end

let load file = Archive.(to_index @@ load file)
let save t = Archive.(save @@ of_index t)
