(* Typed S-expression serializers for the Dlg (DLG/TLK strings), Dc (.d
 * actions), TRA and WeiDU.log AST types.  See Astdump for the writer
 * conventions and doc/trace/ast/README.md for the format specification. *)

open Astdump
open Util

(* -- Dlg -- *)

let string_or_int o (s : Dlg.string_or_int) =
  line_start o ;
  (match s with
  | Dlg.Int i -> node_start o "dlg.string_or_int.int" ; int o i
  | Dlg.String s -> node_start o "dlg.string_or_int.string" ; str o s) ;
  node_end o

let local_string_entry o (l : local_string_entry) =
  line_start o ;
  node_start o "local_string_entry" ;
  f_str o "lse_male" l.lse_male ;
  f_str o "lse_male_sound" l.lse_male_sound ;
  f_str o "lse_female" l.lse_female ;
  f_str o "lse_female_sound" l.lse_female_sound ;
  node_end o

let tlk_string o (t : Dlg.tlk_string) =
  line_start o ;
  (match t with
  | Dlg.TLK_Index i ->
      node_start o "dlg.tlk_string.tlk_index" ; int o i
  | Dlg.Local_String l ->
      node_start o "dlg.tlk_string.local_string" ; local_string_entry o l
  | Dlg.Trans_String s ->
      node_start o "dlg.tlk_string.trans_string" ; string_or_int o s) ;
  node_end o

let weight o (w : Dlg.weight) =
  line_start o ;
  (match w with
  | Dlg.Not_Specified -> node_start o "dlg.weight.not_specified"
  | Dlg.Offset i -> node_start o "dlg.weight.offset" ; int o i) ;
  node_end o

let journal_type o (j : Dlg.journal_type) =
  line_start o ;
  (match j with
  | Dlg.Normal_Journal -> node_start o "dlg.journal_type.normal_journal"
  | Dlg.Solved_Journal -> node_start o "dlg.journal_type.solved_journal"
  | Dlg.Unsolved_Journal -> node_start o "dlg.journal_type.unsolved_journal") ;
  node_end o

let trans_next o (n : Dlg.trans_next) =
  line_start o ;
  (match n with
  | Dlg.Exit ->
      node_start o "dlg.trans_next.exit" ;
      node_end o
  | Dlg.Absolute (f, i) ->
      node_start o "dlg.trans_next.absolute" ;
      f_str o "arg-1" f ;
      f_int o "arg-2" i ;
      node_end o
  | Dlg.Symbolic (f, l, e) ->
      node_start o "dlg.trans_next.symbolic" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" l ;
      f_bool o "arg-3" e ;
      node_end o
  | Dlg.Copy (f, l, e) ->
      node_start o "dlg.trans_next.copy" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" l ;
      f_bool o "arg-3" e ;
      node_end o
  | Dlg.Copy_Late (f, l, e) ->
      node_start o "dlg.trans_next.copy_late" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" l ;
      f_bool o "arg-3" e ;
      node_end o)

let transition o (t : Dlg.transition) =
  line_start o ;
  node_start o "dlg.transition" ;
  f_int o "unknown_flags" t.Dlg.unknown_flags ;
  f_opt o "trans_str" tlk_string t.Dlg.trans_str ;
  f_opt o "journal_str" (pair journal_type tlk_string) t.Dlg.journal_str ;
  f_opt o "trans_trigger" str t.Dlg.trans_trigger ;
  f_opt o "action" str t.Dlg.action ;
  f_node o "next" trans_next t.Dlg.next ;
  node_end o

let state o (s : Dlg.state) =
  line_start o ;
  node_start o "dlg.state" ;
  f_node o "resp_str" tlk_string s.Dlg.resp_str ;
  f_array o "trans" transition s.Dlg.trans ;
  f_str o "state_trigger" s.Dlg.state_trigger ;
  f_node o "state_trigger_weight" weight s.Dlg.state_trigger_weight ;
  f_str o "symbolic_label" s.Dlg.symbolic_label ;
  node_end o

let dlg o (d : Dlg.dlg) =
  line_start o ;
  node_start o "dlg.dlg" ;
  f_str o "name" d.Dlg.name ;
  f_array o "state" state d.Dlg.state ;
  f_int o "dlg_flags" d.Dlg.dlg_flags ;
  node_end o

(* -- Dc -- *)

let d_when o (w : Dc.d_when) =
  line_start o ;
  (match w with
  | Dc.W_If s -> node_start o "dc.d_when.w_if" ; str o s
  | Dc.W_Unless s -> node_start o "dc.d_when.w_unless" ; str o s) ;
  node_end o

let alter_trans_feature o (f : Dc.alter_trans_feature) =
  line_start o ;
  (match f with
  | Dc.Alter_Trans_String s ->
      node_start o "dc.alter_trans_feature.alter_trans_string" ; str o s
  | Dc.Alter_Trans_Lse ts ->
      node_start o "dc.alter_trans_feature.alter_trans_lse" ; tlk_string o ts) ;
  node_end o

let chain_info o (c : Dc.chain_info) =
  line_start o ;
  node_start o "dc.chain_info" ;
  f_str o "entry_file" c.Dc.entry_file ;
  f_str o "entry_label" c.Dc.entry_label ;
  f_list o "dialogue" (pair str tlk_string) c.Dc.dialogue ;
  f_str o "exit_file" c.Dc.exit_file ;
  f_str o "exit_label" c.Dc.exit_label ;
  node_end o

let c3_dialogue_unit o (u : Dc.c3_dialogue_unit) =
  line_start o ;
  node_start o "dc.c3_dialogue_unit" ;
  f_str o "c3du_speaker" u.Dc.c3du_speaker ;
  f_opt o "c3du_condition" str u.Dc.c3du_condition ;
  f_opt o "c3du_action" str u.Dc.c3du_action ;
  f_node o "c3du_say" tlk_string u.Dc.c3du_say ;
  f_int o "c3du_id" u.Dc.c3du_id ;
  f_bool o "c3du_ifexists" u.Dc.c3du_ifexists ;
  node_end o

let chain3_info o (c : Dc.chain3_info) =
  line_start o ;
  node_start o "dc.chain3_info" ;
  f_opt o "c3_entry_condition" str c.Dc.c3_entry_condition ;
  f_node o "c3_entry_weight" weight c.Dc.c3_entry_weight ;
  f_str o "c3_entry_file" c.Dc.c3_entry_file ;
  f_bool o "c3_iffileexists" c.Dc.c3_iffileexists ;
  f_str o "c3_entry_label" c.Dc.c3_entry_label ;
  f_list o "c3_dialogue" c3_dialogue_unit c.Dc.c3_dialogue ;
  f_array o "c3_exit_trans" transition c.Dc.c3_exit_trans ;
  f_opt o "c3_variable" str c.Dc.c3_variable ;
  f_bool o "c3_keep_first_do_with_first_speaker"
      c.Dc.c3_keep_first_do_with_first_speaker ;
  f_bool o "c3_append_all" c.Dc.c3_append_all ;
  node_end o

let action o (a : Dc.action) =
  line_start o ;
  (match a with
  | Dc.Create d ->
      node_start o "dc.action.create" ;
      dlg o d ;
      node_end o
  | Dc.Append (f, b, states) ->
      node_start o "dc.action.append" ;
      f_str o "arg-1" f ;
      f_bool o "arg-2" b ;
      f_list o "arg-3" state states ;
      node_end o
  | Dc.Append_Early (f, b, states) ->
      node_start o "dc.action.append_early" ;
      f_str o "arg-1" f ;
      f_bool o "arg-2" b ;
      f_list o "arg-3" state states ;
      node_end o
  | Dc.Extend_Bottom (f, labels, i, trans) ->
      node_start o "dc.action.extend_bottom" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_int o "arg-3" i ;
      f_list o "arg-4" transition trans ;
      node_end o
  | Dc.Extend_Top (f, labels, i, trans) ->
      node_start o "dc.action.extend_top" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_int o "arg-3" i ;
      f_list o "arg-4" transition trans ;
      node_end o
  | Dc.Replace (f, states) ->
      node_start o "dc.action.replace" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" state states ;
      node_end o
  | Dc.Replace_Say (f, l, ts) ->
      node_start o "dc.action.replace_say" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" l ;
      f_node o "arg-3" tlk_string ts ;
      node_end o
  | Dc.Add_Trans_Trigger (f, labels, s2, strs, whens) ->
      node_start o "dc.action.add_trans_trigger" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_str o "arg-3" s2 ;
      f_list o "arg-4" str strs ;
      f_list o "arg-5" d_when whens ;
      node_end o
  | Dc.Add_Trans_Action (f, labels, nums, s2, whens) ->
      node_start o "dc.action.add_trans_action" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_list o "arg-3" int nums ;
      f_str o "arg-4" s2 ;
      f_list o "arg-5" d_when whens ;
      node_end o
  | Dc.Alter_Trans (f, labels, nums, alters) ->
      node_start o "dc.action.alter_trans" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_list o "arg-3" int nums ;
      f_list o "arg-4" (pair str alter_trans_feature) alters ;
      node_end o
  | Dc.Replace_Trans_Action (f, labels, nums, s2, s3, whens) ->
      node_start o "dc.action.replace_trans_action" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_list o "arg-3" int nums ;
      f_str o "arg-4" s2 ;
      f_str o "arg-5" s3 ;
      f_list o "arg-6" d_when whens ;
      node_end o
  | Dc.Replace_Trans_Trigger (f, labels, nums, s2, s3, whens) ->
      node_start o "dc.action.replace_trans_trigger" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_list o "arg-3" int nums ;
      f_str o "arg-4" s2 ;
      f_str o "arg-5" s3 ;
      f_list o "arg-6" d_when whens ;
      node_end o
  | Dc.Replace_State_Trigger (f, labels, s2, whens) ->
      node_start o "dc.action.replace_state_trigger" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_str o "arg-3" s2 ;
      f_list o "arg-4" d_when whens ;
      node_end o
  | Dc.Add_State_Trigger (f, labels, s2, whens) ->
      node_start o "dc.action.add_state_trigger" ;
      f_str o "arg-1" f ;
      f_list o "arg-2" str labels ;
      f_str o "arg-3" s2 ;
      f_list o "arg-4" d_when whens ;
      node_end o
  | Dc.Set_Weight (f, l, i) ->
      node_start o "dc.action.set_weight" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" l ;
      f_int o "arg-3" i ;
      node_end o
  | Dc.Chain ci ->
      node_start o "dc.action.chain" ;
      chain_info o ci ;
      node_end o
  | Dc.Replace_Action_Text (fs, s2, s3, b, whens) ->
      node_start o "dc.action.replace_action_text" ;
      f_list o "arg-1" str fs ;
      f_str o "arg-2" s2 ;
      f_str o "arg-3" s3 ;
      f_bool o "arg-4" b ;
      f_list o "arg-5" d_when whens ;
      node_end o
  | Dc.Replace_Trigger_Text (f, s2, s3, b, whens) ->
      node_start o "dc.action.replace_trigger_text" ;
      f_str o "arg-1" f ;
      f_str o "arg-2" s2 ;
      f_str o "arg-3" s3 ;
      f_bool o "arg-4" b ;
      f_list o "arg-5" d_when whens ;
      node_end o
  | Dc.Chain3 c3 ->
      node_start o "dc.action.chain3" ;
      chain3_info o c3 ;
      node_end o)

let d_file o (l : Dc.action list) =
  line_start o ;
  node_start o "dc.d_file" ;
  f_list o "list" action l ;
  node_end o

(* -- TRA -- *)

(* Dparser.tra_file: (strref number * text) entries. *)
let tra_entry o ((i, ts) : int * Dlg.tlk_string) =
  line_start o ;
  node_start o "tra.entry" ;
  f_int o "str_ref" i ;
  f_node o "text" tlk_string ts ;
  node_end o

let tra_file o (l : (int * Dlg.tlk_string) list) =
  line_start o ;
  node_start o "tra.tra_file" ;
  f_list o "list" tra_entry l ;
  node_end o

(* -- WeiDU.log -- *)

let log_entry o ((name, v1, v2, sub) : string * int * int * string option) =
  line_start o ;
  node_start o "log.entry" ;
  f_str o "mod_name" name ;
  f_int o "version_major" v1 ;
  f_int o "version_minor" v2 ;
  f_opt o "sub_name" str sub ;
  node_end o

let log_file o (l : (string * int * int * (string option)) list) =
  line_start o ;
  node_start o "log.log_file" ;
  f_list o "list" log_entry l ;
  node_end o

(* -- dump entry points -- *)

let dump_d_actions stage source l =
  write_dump "d" stage source (fun o -> d_file o l)

let dump_tra stage source l =
  write_dump "tra" stage source (fun o -> tra_file o l)

let dump_log stage source l =
  write_dump "log" stage source (fun o -> log_file o l)
