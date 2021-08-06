open Import
open Ast_builder.Default

let underscore_binding exp =
  let loc = exp.pexp_loc in
  value_binding ~loc ~pat:(ppat_any ~loc) ~expr:exp

let vars_of = object
  inherit [Longident.t Located.t list] Ast_traverse.fold as super
  method! pattern patt acc =
    match patt.ppat_desc with
    | Ppat_var v -> Located.map (fun var -> Longident.Lident var) v :: acc
    | _ -> super#pattern patt acc
end

(* For every [let x = ...] structure item, add a [let _ = x] *)
let add_dummy_user_for_values = object
  inherit Ast_traverse.map as super
  method! structure st =
    let rec loop st acc =
      match st with
      | [] -> List.rev acc
      | { pstr_desc = Pstr_value (_, vbs); pstr_loc = loc } as item :: rest ->
        let vars =
          List.fold_left vbs ~init:[] ~f:(fun acc vb -> vars_of#pattern vb.pvb_pat acc)
        in
        let ign =
          pstr_value_list ~loc Nonrecursive
            (List.rev_map vars ~f:(fun v ->
               underscore_binding (pexp_ident ~loc:v.loc v)))
        in
        loop rest (ign @ (item :: acc))
      | item :: rest ->
        loop rest (item :: acc)
    in
    loop (super#structure st) []
end

let binds_module_names = object
  inherit [bool] Ast_traverse.fold as super

  method! structure_item item acc =
    match item.pstr_desc with
    | Pstr_module _ -> true
    | Pstr_recmodule _ -> true
    | _ -> super#structure_item item acc

  method! signature_item item acc =
    match item.psig_desc with
    | Psig_module _ -> true
    | Psig_modsubst _ -> true
    | Psig_recmodule _ -> true
    | _ -> super#signature_item item acc

  method! module_expr me acc =
    match me.pmod_desc with
    | Pmod_functor _ -> true
    | _ -> super#module_expr me acc

  method! pattern pat acc =
    match pat.ppat_desc with
    | Ppat_unpack _ -> true
    | _ -> super#pattern pat acc

  method! expression expr acc =
    match expr.pexp_desc with
    | Pexp_letmodule _ -> true
    | _ -> super#expression expr acc
end
