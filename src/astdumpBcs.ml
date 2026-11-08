(* Typed S-expression serializers for the Bcs (BAF/BCS scripts), Ids and
 * Refactorbaf AST types.  See Astdump for the writer conventions and
 * doc/trace/ast/README.md for the format specification. *)

open Astdump
open Util

(* -- Bcs -- *)

let object_param o (p : Bcs.object_param) =
  line_start o ;
  node_start o "bcs.object_param" ;
  f_i32 o "o_ea" p.Bcs.o_ea ;
  f_i32 o "o_faction" p.Bcs.o_faction ;
  f_i32 o "o_team" p.Bcs.o_team ;
  f_i32 o "o_general" p.Bcs.o_general ;
  f_i32 o "o_race" p.Bcs.o_race ;
  f_i32 o "o_subrace" p.Bcs.o_subrace ;
  f_i32 o "o_class" p.Bcs.o_class ;
  f_i32 o "o_specific" p.Bcs.o_specific ;
  f_i32 o "o_gender" p.Bcs.o_gender ;
  f_i32 o "o_alignment" p.Bcs.o_alignment ;
  f_i32 o "o_identifiers" p.Bcs.o_identifiers ;
  f_i32 o "o_unknown1" p.Bcs.o_unknown1 ;
  f_i32 o "o_unknown2" p.Bcs.o_unknown2 ;
  f_i32 o "o_unknown3" p.Bcs.o_unknown3 ;
  f_i32 o "o_unknown4" p.Bcs.o_unknown4 ;
  f_str o "o_name" p.Bcs.o_name ;
  f_node o "o_rect"
      (fun o (a, b, c, d) ->
        line_start o ;
        node_start o "bcs.rect_param" ;
        f_i32 o "x1" a ;
        f_i32 o "y1" b ;
        f_i32 o "x2" c ;
        f_i32 o "y2" d ;
        node_end o) p.Bcs.o_rect ;
  f_i32 o "o_iwd2_1" p.Bcs.o_iwd2_1 ;
  f_i32 o "o_iwd2_2" p.Bcs.o_iwd2_2 ;
  node_end o

let point_param o ((x, y) : Bcs.point_param) =
  line_start o ;
  node_start o "bcs.point_param" ;
  f_i32 o "x" x ;
  f_i32 o "y" y ;
  node_end o

let trigger o (t : Bcs.trigger) =
  line_start o ;
  node_start o "bcs.trigger" ;
  f_i32 o "trigger_id" t.Bcs.trigger_id ;
  f_bool o "negated" t.Bcs.negated ;
  f_i32 o "t_1" t.Bcs.t_1 ;
  f_i32 o "t_2" t.Bcs.t_2 ;
  f_str o "t_3" t.Bcs.t_3 ;
  f_str o "t_4" t.Bcs.t_4 ;
  f_node o "t_5" object_param t.Bcs.t_5 ;
  f_node o "t_coord" point_param t.Bcs.t_coord ;
  f_i32 o "unknown" t.Bcs.unknown ;
  node_end o

let action o (a : Bcs.action) =
  line_start o ;
  node_start o "bcs.action" ;
  f_i32 o "action_id" a.Bcs.action_id ;
  f_node o "a_1" object_param a.Bcs.a_1 ;
  f_node o "a_2" object_param a.Bcs.a_2 ;
  f_node o "a_3" object_param a.Bcs.a_3 ;
  f_i32 o "a_4" a.Bcs.a_4 ;
  f_node o "a_5" point_param a.Bcs.a_5 ;
  f_i32 o "a_6" a.Bcs.a_6 ;
  f_i32 o "a_7" a.Bcs.a_7 ;
  f_str o "a_8" a.Bcs.a_8 ;
  f_str o "a_9" a.Bcs.a_9 ;
  node_end o

(* Bcs.response = int * Bcs.action list *)
let response o ((weight, actions) : Bcs.response) =
  line_start o ;
  node_start o "bcs.response" ;
  f_int o "weight" weight ;
  f_list o "actions" action actions ;
  node_end o

(* Bcs.condition = Bcs.trigger list *)
let condition o (triggers : Bcs.trigger list) =
  line_start o ;
  node_start o "bcs.condition" ;
  f_list o "triggers" trigger triggers ;
  node_end o

let condition_response o ((c, rs) : Bcs.condition_response) =
  line_start o ;
  node_start o "bcs.condition_response" ;
  f_node o "condition" condition c ;
  f_list o "responses" response rs ;
  node_end o

(* Bcs.script = Bcs.condition_response list *)
let script o (s : Bcs.script) =
  line_start o ;
  node_start o "bcs.script" ;
  f_list o "list" condition_response s ;
  node_end o

let dump_script grammar stage source s =
  write_dump grammar stage source (fun o -> script o s)

(* -- Ids -- *)

let arg_kind o (k : Ids.arg_kind) =
  line_start o ;
  (match k with
  | Ids.Arg_Object -> node_start o "ids.arg_kind.arg_object"
  | Ids.Arg_Action -> node_start o "ids.arg_kind.arg_action"
  | Ids.Arg_Point -> node_start o "ids.arg_kind.arg_point"
  | Ids.Arg_String -> node_start o "ids.arg_kind.arg_string"
  | Ids.Arg_Integer -> node_start o "ids.arg_kind.arg_integer") ;
  node_end o

let i_arg o (a : Ids.i_arg) =
  line_start o ;
  node_start o "ids.i_arg" ;
  f_node o "arg_kind" arg_kind a.Ids.arg_kind ;
  f_str o "arg_comment" a.Ids.arg_comment ;
  f_str o "arg_file" a.Ids.arg_file ;
  node_end o

let ids_entry o (e : Ids.ids) =
  line_start o ;
  node_start o "ids.ids" ;
  f_i32 o "i_num" e.Ids.i_num ;
  f_str o "i_name" e.Ids.i_name ;
  f_list o "i_args" i_arg e.Ids.i_args ;
  node_end o

let ids_file o (l : Ids.ids list) =
  line_start o ;
  node_start o "ids.ids_file" ;
  f_list o "list" ids_entry l ;
  node_end o

let dump_ids stage source l =
  write_dump "ids" stage source (fun o -> ids_file o l)

(* -- Refactorbaf -- *)

let rec refactorbaf_trigger o (t : Refactorbaf.trigger) =
  line_start o ;
  (match t with
  | Refactorbaf.Or tl ->
      node_start o "refactorbaf.trigger.or" ;
      f_list o "triggers" refactorbaf_trigger tl ;
      node_end o
  | Refactorbaf.Trigger (s, a) ->
      node_start o "refactorbaf.trigger.trigger" ;
      f_str o "trigger" s ;
      f_opt o "actor" str a ;
      node_end o
  | Refactorbaf.NotTrigger (s, a) ->
      node_start o "refactorbaf.trigger.not_trigger" ;
      f_str o "trigger" s ;
      f_opt o "actor" str a ;
      node_end o)

let refactorbaf_trigger_list o (l : Refactorbaf.trigger list) =
  line_start o ;
  node_start o "refactorbaf.trigger_list" ;
  f_list o "list" refactorbaf_trigger l ;
  node_end o

let dump_refactorbaf_triggers stage source l =
  write_dump "refactorbaf" stage source (fun o -> refactorbaf_trigger_list o l)
