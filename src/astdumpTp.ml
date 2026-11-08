(* Typed S-expression serializers for the Tp (TP2/TPA/TPP) AST types.
 * See Astdump for the writer conventions and doc/trace/ast/README.md for
 * the format specification.  Every constructor of every serialized type
 * is handled
 * explicitly (no wildcard matches) so that the compiler keeps this file
 * in sync with src/tp.ml. *)

open Astdump
open AstdumpDlg
open Util

(* -- auxiliary shared types -- *)

let rec script_style o (s : Load.script_style) =
  line_start o ;
  (match s with
  | Load.BG1 -> node_start o "load.script_style.bg1"
  | Load.BG2 -> node_start o "load.script_style.bg2"
  | Load.IWD1 -> node_start o "load.script_style.iwd1"
  | Load.IWD2 -> node_start o "load.script_style.iwd2"
  | Load.PST -> node_start o "load.script_style.pst"
  | Load.NONE -> node_start o "load.script_style.none") ;
  node_end o

(* -- expression leaves (no recursion up here) -- *)

and tp_pe_string o (p : Tp.tp_pe_string) =
  line_start o ;
  (match p with
  | Tp.PE_LiteralString s ->
      node_start o "tp_pe_string.pe_literalstring" ;
      str o s ;
      node_end o
  | Tp.PE_GetVar p ->
      node_start o "tp_pe_string.pe_getvar" ;
      tp_pe_string o p ;
      node_end o
  | Tp.PE_Evaluate p ->
      node_start o "tp_pe_string.pe_evaluate" ;
      tp_pe_string o p ;
      node_end o
  | Tp.PE_Lowercase p ->
      node_start o "tp_pe_string.pe_lowercase" ;
      tp_pe_string o p ;
      node_end o
  | Tp.PE_Uppercase p ->
      node_start o "tp_pe_string.pe_uppercase" ;
      tp_pe_string o p ;
      node_end o
  | Tp.PE_Dollars (p, pl, b1, b2) ->
      node_start o "tp_pe_string.pe_dollars" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list tp_pe_string) pl ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      node_end o)

and tp_pe_tlk o (p : Tp.tp_pe_tlk_string) =
  line_start o ;
  (match p with
  | Tp.PE_Tlk ts ->
      node_start o "tp_pe_tlk_string.pe_tlk" ;
      tlk_string o ts ;
      node_end o
  | Tp.PE_Pe p ->
      node_start o "tp_pe_tlk_string.pe_pe" ;
      tp_pe_string o p ;
      node_end o)

and tp_array_construct o (a : Tp.tp_array_construct) =
  line_start o ;
  (match a with
  | Tp.PE_Dollars (p, pl, b1, b2) ->
      node_start o "tp_array_construct.pe_dollars" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list tp_pe_string) pl ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      node_end o)

and tp_cache_arg o (c : Tp.tp_cache_arg) =
  line_start o ;
  (match c with
  | Tp.TP_ClearCache -> node_start o "tp_cache_arg.tpclearcache"
  | Tp.TP_Cache -> node_start o "tp_cache_arg.tpcache") ;
  node_end o

and array_indices_sort_type o (s : Tp.array_indices_sort_type) =
  line_start o ;
  (match s with
  | Tp.TP_Lexicographically -> node_start o "array_indices_sort_type.tp_lexicographically"
  | Tp.TP_Numerically -> node_start o "array_indices_sort_type.tp_numerically") ;
  node_end o

and file_or_directory_regexp o (f : Tp.file_or_directory_regexp) =
  line_start o ;
  (match f with
  | Tp.TP_File s ->
      node_start o "file_or_directory_regexp.tp_file" ;
      str o s ;
      node_end o
  | Tp.TP_Directory_Regexp (s1, bo, s2) ->
      node_start o "file_or_directory_regexp.tp_directory_regexp" ;
      f_str o "arg-1" s1 ;
      f_opt o "arg-2" bool bo ;
      f_str o "arg-3" s2 ;
      node_end o)

and tp_decompress_where o (d : Tp.tp_decompress_where) =
  line_start o ;
  (match d with
  | Tp.TP_DW_ReplaceFile ->
      node_start o "tp_decompress_where.tp_dw_replacefile" ;
      node_end o
  | Tp.TP_DW_Variable p ->
      node_start o "tp_decompress_where.tp_dw_variable" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_DW_IntoFile (e1, e2) ->
      node_start o "tp_decompress_where.tp_dw_intofile" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o)

and tp_store_position o (s : Tp.tp_store_position) =
  line_start o ;
  (match s with
  | Tp.TP_Store_First ->
      node_start o "tp_store_position.tp_store_first" ;
      node_end o
  | Tp.TP_Store_Last ->
      node_start o "tp_store_position.tp_store_last" ;
      node_end o
  | Tp.TP_Store_At e ->
      node_start o "tp_store_position.tp_store_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_Store_After p ->
      node_start o "tp_store_position.tp_store_after" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_Store_Before p ->
      node_start o "tp_store_position.tp_store_before" ;
      tp_pe_string o p ;
      node_end o)

and tp_constraint o (c : Tp.tp_constraint) =
  line_start o ;
  (match c with
  | Tp.TP_Contains p ->
      node_start o "tp_constraint.tp_contains" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_NotContains p ->
      node_start o "tp_constraint.tp_notcontains" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_IfSizeIs i ->
      node_start o "tp_constraint.tp_ifsizeis" ;
      int o i ;
      node_end o
  | Tp.TP_Eval e ->
      node_start o "tp_constraint.tp_eval" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_ButOnlyIfItChanges ->
      node_start o "tp_constraint.tp_butonlyifitchanges" ;
      node_end o
  | Tp.TP_IfExists ->
      node_start o "tp_constraint.tp_ifexists" ;
      node_end o)

(* -- records used by actions and patches -- *)

and tp_copy_args o (c : Tp.tp_copy_args) =
  line_start o ;
  node_start o "tp_copy_args" ;
  f_bool o "copy_get_existing" c.Tp.copy_get_existing ;
  f_bool o "copy_use_regexp" c.Tp.copy_use_regexp ;
  f_bool o "copy_use_glob" c.Tp.copy_use_glob ;
  f_list o "copy_file_list" (pair str str) c.Tp.copy_file_list ;
  f_list o "copy_patch_list" tp_patch c.Tp.copy_patch_list ;
  f_list o "copy_constraint_list" tp_constraint c.Tp.copy_constraint_list ;
  f_bool o "copy_backup" c.Tp.copy_backup ;
  f_bool o "copy_at_end" c.Tp.copy_at_end ;
  f_bool o "copy_save_inlined" c.Tp.copy_save_inlined ;
  node_end o

and tp_copy_large_args o (c : Tp.tp_copy_large_args) =
  line_start o ;
  node_start o "tp_copy_large_args" ;
  f_bool o "copy_large_use_glob" c.Tp.copy_large_use_glob ;
  f_list o "copy_large_file_list" (pair str str) c.Tp.copy_large_file_list ;
  f_bool o "copy_large_backup" c.Tp.copy_large_backup ;
  node_end o

and store_args o (s : Tp.store_args) =
  line_start o ;
  node_start o "store_args" ;
  f_bool o "overwrite_store_item" s.Tp.overwrite_store_item ;
  node_end o

and tp_add_kit o (k : Tp.tp_add_kit) =
  line_start o ;
  node_start o "tp_add_kit" ;
  f_str o "kit_name" k.Tp.kit_name ;
  f_str o "clasweap" k.Tp.clasweap ;
  f_str o "weapprof" k.Tp.weapprof ;
  f_str o "abclasrq" k.Tp.abclasrq ;
  f_str o "abclsmod" k.Tp.abclsmod ;
  f_str o "abdcdsrq" k.Tp.abdcdsrq ;
  f_str o "abdcscrq" k.Tp.abdcscrq ;
  f_str o "dualclas" k.Tp.dualclas ;
  f_str o "alignmnt" k.Tp.alignmnt ;
  f_str o "ability_file" k.Tp.ability_file ;
  f_str o "include_in" k.Tp.include_in ;
  f_node o "lower" tlk_string k.Tp.lower ;
  f_node o "mixed" tlk_string k.Tp.mixed ;
  f_node o "help" tlk_string k.Tp.help ;
  f_str o "unused_class" k.Tp.unused_class ;
  f_list o "tob_start" str k.Tp.tob_start ;
  f_str o "tob_abbr" k.Tp.tob_abbr ;
  node_end o

and tp_add_map_note o (m : Tp.tp_add_map_note) =
  line_start o ;
  node_start o "tp_add_map_note" ;
  f_node o "xcoord" tp_patchexp m.Tp.xcoord ;
  f_node o "ycoord" tp_patchexp m.Tp.ycoord ;
  f_node o "mstring" tlk_string m.Tp.mstring ;
  f_str o "colour" m.Tp.colour ;
  node_end o

and tp_add_cre_item o (c : Tp.tp_add_cre_item) =
  line_start o ;
  node_start o "tp_add_cre_item" ;
  f_str o "item_name" c.Tp.item_name ;
  f_node o "i_charge1" tp_patchexp c.Tp.i_charge1 ;
  f_node o "i_charge2" tp_patchexp c.Tp.i_charge2 ;
  f_node o "i_charge3" tp_patchexp c.Tp.i_charge3 ;
  f_str o "i_flags" c.Tp.i_flags ;
  f_str o "item_slot" c.Tp.item_slot ;
  f_bool o "equip" c.Tp.equip ;
  f_bool o "twohanded_weapon" c.Tp.twohanded_weapon ;
  f_bool o "nomove" c.Tp.nomove ;
  node_end o

and tp_add_music o (m : Tp.tp_add_music) =
  line_start o ;
  node_start o "tp_add_music" ;
  f_str o "music_name" m.Tp.music_name ;
  f_str o "music_file" m.Tp.music_file ;
  node_end o

and tp_add_projectile o (p : Tp.tp_add_projectile) =
  line_start o ;
  node_start o "tp_add_projectile" ;
  f_str o "pro_file" p.Tp.pro_file ;
  f_str o "missile_ids_name" p.Tp.missile_ids_name ;
  node_end o

and tp_local_declaration o (d : Tp.tp_local_declaration) =
  line_start o ;
  (match d with
  | Tp.TP_LocalSet (p, e) ->
      node_start o "tp_local_declaration.tp_localset" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TP_LocalSprint (p1, p2) ->
      node_start o "tp_local_declaration.tp_localsprint" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_tlk p2 ;
      node_end o
  | Tp.TP_LocalTextSprint (p1, p2) ->
      node_start o "tp_local_declaration.tp_localtextsprint" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o)

(* -- tp_action -- *)

and tp_action o (a : Tp.tp_action) =
  line_start o ;
  (match a with
  | Tp.TP_ActionBashFor (pats, acts) ->
      node_start o "tp_action.tp_actionbashfor" ;
      f_node o "arg-1" (v_list (triple str (v_opt bool) str)) pats ;
      f_node o "arg-2" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_ActionDefineArray (p, l) ->
      node_start o "tp_action.tp_actiondefinearray" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list str) l ;
      node_end o
  | Tp.TP_ActionSortArrayIndices (p, s) ->
      node_start o "tp_action.tp_actionsortarrayindices" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" array_indices_sort_type s ;
      node_end o
  | Tp.TP_ActionPHPEach (p1, p2, p3, acts) ->
      node_start o "tp_action.tp_actionphpeach" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_node o "arg-3" tp_pe_string p3 ;
      f_node o "arg-4" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Action_For_Each (p, l, acts) ->
      node_start o "tp_action.tp_action_for_each" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list str) l ;
      f_node o "arg-3" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Action_ReadLN p ->
      node_start o "tp_action.tp_action_readln" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_ClearMemory ->
      node_start o "tp_action.tp_clearmemory" ; node_end o
  | Tp.TP_ClearArrays ->
      node_start o "tp_action.tp_cleararrays" ; node_end o
  | Tp.TP_ClearCodes ->
      node_start o "tp_action.tp_clearcodes" ; node_end o
  | Tp.TP_ClearInlined ->
      node_start o "tp_action.tp_clearinlined" ; node_end o
  | Tp.TP_Clear_Ids_Map ->
      node_start o "tp_action.tp_clear_ids_map" ; node_end o
  | Tp.TP_ClearEverything ->
      node_start o "tp_action.tp_cleareverything" ; node_end o
  | Tp.TP_ActionClearArray p ->
      node_start o "tp_action.tp_actioncleararray" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_CopyAllGamFiles (pl, cl) ->
      node_start o "tp_action.tp_copyallgamfiles" ;
      f_node o "arg-1" (v_list tp_patch) pl ;
      f_node o "arg-2" (v_list tp_constraint) cl ;
      node_end o
  | Tp.TP_Copy ca ->
      node_start o "tp_action.tp_copy" ;
      tp_copy_args o ca ;
      node_end o
  | Tp.TP_Move (l, b) ->
      node_start o "tp_action.tp_move" ;
      f_node o "arg-1" (v_list (pair file_or_directory_regexp str)) l ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_Delete (pl, b) ->
      node_start o "tp_action.tp_delete" ;
      f_node o "arg-1" (v_list tp_pe_string) pl ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_DisableFromKey pl ->
      node_start o "tp_action.tp_disablefromkey" ;
      v_list tp_pe_string o pl ;
      node_end o
  | Tp.TP_CopyLarge cla ->
      node_start o "tp_action.tp_copylarge" ;
      tp_copy_large_args o cla ;
      node_end o
  | Tp.TP_CopyRandom (sll, pl, cl) ->
      node_start o "tp_action.tp_copyrandom" ;
      f_node o "arg-1" (v_list (v_list str)) sll ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      f_node o "arg-3" (v_list tp_constraint) cl ;
      node_end o
  | Tp.TP_RandomSeed e ->
      node_start o "tp_action.tp_randomseed" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_Compile (b, sl, pl, sl2) ->
      node_start o "tp_action.tp_compile" ;
      f_bool o "arg-1" b ;
      f_node o "arg-2" (v_list str) sl ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      f_node o "arg-4" (v_list str) sl2 ;
      node_end o
  | Tp.TP_Launch_Action_Macro s ->
      node_start o "tp_action.tp_launch_action_macro" ;
      str o s ;
      node_end o
  | Tp.TP_Launch_Action_Function (s, l1, l2, l3, l4) ->
      node_start o "tp_action.tp_launch_action_function" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list (pair tp_pe_string tp_patchexp)) l1 ;
      f_node o "arg-3" (v_list (pair tp_pe_string tp_pe_string)) l2 ;
      f_node o "arg-4" (v_list (pair tp_pe_string tp_pe_string)) l3 ;
      f_node o "arg-5" (v_list (pair tp_pe_string tp_pe_string)) l4 ;
      node_end o
  | Tp.TP_Reinclude sl ->
      node_start o "tp_action.tp_reinclude" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Include sl ->
      node_start o "tp_action.tp_include" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Load_Tra sl ->
      node_start o "tp_action.tp_load_tra" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Inlined_File (s1, s2) ->
      node_start o "tp_action.tp_inlined_file" ;
      pair str str o (s1, s2) ;
      node_end o
  | Tp.TP_GetFileArray (p1, p2, p3, b) ->
      node_start o "tp_action.tp_getfilearray" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_node o "arg-3" tp_pe_string p3 ;
      f_bool o "arg-4" b ;
      node_end o
  | Tp.TP_GetResourceArray (p1, p2) ->
      node_start o "tp_action.tp_getresourcearray" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.TP_Define_Action_Macro (s, ld, acts) ->
      node_start o "tp_action.tp_define_action_macro" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_local_declaration) ld ;
      f_node o "arg-3" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Define_Patch_Macro (s, ld, pl) ->
      node_start o "tp_action.tp_define_patch_macro" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_local_declaration) ld ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Define_Patch_Function (s, l1, l2, l3, l4, pl) ->
      node_start o "tp_action.tp_define_patch_function" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list (pair tp_pe_string tp_patchexp)) l1 ;
      f_node o "arg-3" (v_list (pair tp_pe_string tp_pe_string)) l2 ;
      f_node o "arg-4" (v_list tp_pe_string) l3 ;
      f_node o "arg-5" (v_list tp_pe_string) l4 ;
      f_node o "arg-6" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Define_Action_Function (s, l1, l2, l3, l4, acts) ->
      node_start o "tp_action.tp_define_action_function" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list (pair tp_pe_string tp_patchexp)) l1 ;
      f_node o "arg-3" (v_list (pair tp_pe_string tp_pe_string)) l2 ;
      f_node o "arg-4" (v_list tp_pe_string) l3 ;
      f_node o "arg-5" (v_list tp_pe_string) l4 ;
      f_node o "arg-6" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Define_Dimorphic_Function (s, l1, l2, l3, l4, acts) ->
      node_start o "tp_action.tp_define_dimorphic_function" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list (pair tp_pe_string tp_patchexp)) l1 ;
      f_node o "arg-3" (v_list (pair tp_pe_string tp_pe_string)) l2 ;
      f_node o "arg-4" (v_list tp_pe_string) l3 ;
      f_node o "arg-5" (v_list tp_pe_string) l4 ;
      f_node o "arg-6" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Biff (s, pats) ->
      node_start o "tp_action.tp_biff" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list (triple str (v_opt bool) str)) pats ;
      node_end o
  | Tp.TP_Mkdir sl ->
      node_start o "tp_action.tp_mkdir" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Outer_For (pl, e, pl2, acts) ->
      node_start o "tp_action.tp_outer_for" ;
      f_node o "arg-1" (v_list tp_patch) pl ;
      f_node o "arg-2" tp_patchexp e ;
      f_node o "arg-3" (v_list tp_patch) pl2 ;
      f_node o "arg-4" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Outer_Inner_Buff (s, pl) ->
      node_start o "tp_action.tp_outer_inner_buff" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Outer_Inner_Buff_Save (p, s, pl) ->
      node_start o "tp_action.tp_outer_inner_buff_save" ;
      f_node o "arg-1" tp_pe_string p ;
      f_str o "arg-2" s ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Outer_Set (p, e, b) ->
      node_start o "tp_action.tp_outer_set" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" tp_patchexp e ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_OuterSetIdsSymOfInt (s1, s2, e) ->
      node_start o "tp_action.tp_outersetidssymofint" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" tp_patchexp e ;
      node_end o
  | Tp.TP_Outer_Sprint (p, pt, b) ->
      node_start o "tp_action.tp_outer_sprint" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" tp_pe_tlk pt ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_Outer_Sprintf (p, pt, el) ->
      node_start o "tp_action.tp_outer_sprintf" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" tp_pe_tlk pt ;
      f_node o "arg-3" (v_list tp_patchexp) el ;
      node_end o
  | Tp.TP_Outer_Text_Sprint (p1, p2, b) ->
      node_start o "tp_action.tp_outer_text_sprint" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_Outer_Snprint (e, p, pt) ->
      node_start o "tp_action.tp_outer_snprint" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string p ;
      f_node o "arg-3" tp_pe_tlk pt ;
      node_end o
  | Tp.TP_ActionDefineAssociativeArray (p, l) ->
      node_start o "tp_action.tp_actiondefineassociativearray" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list (pair (v_list tp_pe_string) tp_pe_string)) l ;
      node_end o
  | Tp.TP_Outer_While (e, acts) ->
      node_start o "tp_action.tp_outer_while" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_Require_File (s, ts) ->
      node_start o "tp_action.tp_require_file" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tlk_string ts ;
      node_end o
  | Tp.TP_Forbid_File (s, ts) ->
      node_start o "tp_action.tp_forbid_file" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tlk_string ts ;
      node_end o
  | Tp.TP_Append (s1, s2, cl, b1, b2, i) ->
      node_start o "tp_action.tp_append" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" (v_list tp_constraint) cl ;
      f_bool o "arg-4" b1 ;
      f_bool o "arg-5" b2 ;
      f_int o "arg-6" i ;
      node_end o
  | Tp.TP_Append_Col (s1, s2, e, cl, b, i) ->
      node_start o "tp_action.tp_append_col" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" tp_patchexp e ;
      f_node o "arg-4" (v_list tp_constraint) cl ;
      f_bool o "arg-5" b ;
      f_int o "arg-6" i ;
      node_end o
  | Tp.TP_Set_Col (s, sl, i, cl) ->
      node_start o "tp_action.tp_set_col" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list str) sl ;
      f_int o "arg-3" i ;
      f_node o "arg-4" (v_list tp_constraint) cl ;
      node_end o
  | Tp.TP_Extend_Top (b, s1, s2, pl, sl, cl) ->
      node_start o "tp_action.tp_extend_top" ;
      f_bool o "arg-1" b ;
      f_str o "arg-2" s1 ;
      f_str o "arg-3" s2 ;
      f_node o "arg-4" (v_list tp_patch) pl ;
      f_node o "arg-5" (v_list str) sl ;
      f_node o "arg-6" (v_list tp_constraint) cl ;
      node_end o
  | Tp.TP_Extend_Bottom (b, s1, s2, pl, sl, cl) ->
      node_start o "tp_action.tp_extend_bottom" ;
      f_bool o "arg-1" b ;
      f_str o "arg-2" s1 ;
      f_str o "arg-3" s2 ;
      f_node o "arg-4" (v_list tp_patch) pl ;
      f_node o "arg-5" (v_list str) sl ;
      f_node o "arg-6" (v_list tp_constraint) cl ;
      node_end o
  | Tp.TP_At_Exit (s, b) ->
      node_start o "tp_action.tp_at_exit" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Interactive_Exit (s, b) ->
      node_start o "tp_action.tp_at_interactive_exit" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Uninstall (s, b) ->
      node_start o "tp_action.tp_at_uninstall" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Interactive_Uninstall (s, b) ->
      node_start o "tp_action.tp_at_interactive_uninstall" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Uninstall_Exit (s, b) ->
      node_start o "tp_action.tp_at_uninstall_exit" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Interactive_Uninstall_Exit (s, b) ->
      node_start o "tp_action.tp_at_interactive_uninstall_exit" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_At_Now (po, s, b) ->
      node_start o "tp_action.tp_at_now" ;
      f_opt o "arg-1" tp_pe_string po ;
      f_str o "arg-2" s ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_At_Interactive_Now (po, s, b) ->
      node_start o "tp_action.tp_at_interactive_now" ;
      f_opt o "arg-1" tp_pe_string po ;
      f_str o "arg-2" s ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_Add_Kit k ->
      node_start o "tp_action.tp_add_kit" ;
      tp_add_kit o k ;
      node_end o
  | Tp.TP_CopyKit (s1, s2, l) ->
      node_start o "tp_action.tp_copykit" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" (v_list (pair str str)) l ;
      node_end o
  | Tp.TP_Add_Music m ->
      node_start o "tp_action.tp_add_music" ;
      tp_add_music o m ;
      node_end o
  | Tp.TP_Add_Projectile p ->
      node_start o "tp_action.tp_add_projectile" ;
      tp_add_projectile o p ;
      node_end o
  | Tp.TP_Add_AreaType p ->
      node_start o "tp_action.tp_add_areatype" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_Add_2DA (s, p, ts) ->
      node_start o "tp_action.tp_add_2da" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_pe_string p ;
      f_node o "arg-3" tlk_string ts ;
      node_end o
  | Tp.TP_Add_Spell (s, e1, e2, s2, pl, plo1, plo2) ->
      node_start o "tp_action.tp_add_spell" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e1 ;
      f_node o "arg-3" tp_patchexp e2 ;
      f_str o "arg-4" s2 ;
      f_node o "arg-5" (v_list tp_patch) pl ;
      f_opt o "arg-6" (v_list tp_patch) plo1 ;
      f_opt o "arg-7" (v_list tp_patch) plo2 ;
      node_end o
  | Tp.TP_Silent ->
      node_start o "tp_action.tp_silent" ; node_end o
  | Tp.TP_Verbose ->
      node_start o "tp_action.tp_verbose" ; node_end o
  | Tp.TP_String_Set (l, so) ->
      node_start o "tp_action.tp_string_set" ;
      f_node o "arg-1" (v_list (pair str tlk_string)) l ;
      f_opt o "arg-2" str so ;
      node_end o
  | Tp.TP_String_Set_Evaluate (l, so) ->
      node_start o "tp_action.tp_string_set_evaluate" ;
      f_node o "arg-1" (v_list (pair tp_patchexp tlk_string)) l ;
      f_opt o "arg-2" str so ;
      node_end o
  | Tp.TP_String_Set_Range (e1, e2, s) ->
      node_start o "tp_action.tp_string_set_range" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_str o "arg-3" s ;
      node_end o
  | Tp.TP_Reraise ->
      node_start o "tp_action.tp_reraise" ; node_end o
  | Tp.TP_Fail ts ->
      node_start o "tp_action.tp_fail" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_Abort ts ->
      node_start o "tp_action.tp_abort" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_Warn ts ->
      node_start o "tp_action.tp_warn" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_Print ts ->
      node_start o "tp_action.tp_print" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_Log ts ->
      node_start o "tp_action.tp_log" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_If (e, acts1, acts2) ->
      node_start o "tp_action.tp_if" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" (v_list tp_action) acts1 ;
      f_node o "arg-3" (v_list tp_action) acts2 ;
      node_end o
  | Tp.TP_ActionTry (acts, l) ->
      node_start o "tp_action.tp_actiontry" ;
      f_node o "arg-1" (v_list tp_action) acts ;
      f_node o "arg-2"
          (v_list (triple (v_list tp_patchexp) tp_patchexp (v_list tp_action))) l ;
      node_end o
  | Tp.TP_ActionMatch (e, l) ->
      node_start o "tp_action.tp_actionmatch" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2"
          (v_list (triple (v_list tp_patchexp) tp_patchexp (v_list tp_action))) l ;
      node_end o
  | Tp.TP_Uninstall_Now (s, e) ->
      node_start o "tp_action.tp_uninstall_now" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TP_Alter_TLK pl ->
      node_start o "tp_action.tp_alter_tlk" ;
      v_list tp_patch o pl ;
      node_end o
  | Tp.TP_Alter_TLK_Range (e1, e2, pl) ->
      node_start o "tp_action.tp_alter_tlk_range" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Alter_TLK_List (el, pl) ->
      node_start o "tp_action.tp_alter_tlk_list" ;
      f_node o "arg-1" (v_list tp_patchexp) el ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_DecompressBiff pl ->
      node_start o "tp_action.tp_decompressbiff" ;
      v_list tp_pe_string o pl ;
      node_end o
  | Tp.TP_ActionToLower p ->
      node_start o "tp_action.tp_actiontolower" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_ActionToUpper p ->
      node_start o "tp_action.tp_actiontoupper" ;
      tp_pe_string o p ;
      node_end o
  | Tp.TP_ActionGetStrRef (e, p, b1, b2) ->
      node_start o "tp_action.tp_actiongetstrref" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string p ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      node_end o
  | Tp.TP_AddJournal (b1, b2, tso, tsl, sl) ->
      node_start o "tp_action.tp_addjournal" ;
      f_bool o "arg-1" b1 ;
      f_bool o "arg-2" b2 ;
      f_opt o "arg-3" tlk_string tso ;
      f_node o "arg-4" (v_list tlk_string) tsl ;
      f_node o "arg-5" (v_list str) sl ;
      node_end o
  | Tp.TP_Create (s1, so, s2, pl) ->
      node_start o "tp_action.tp_create" ;
      f_str o "arg-1" s1 ;
      f_opt o "arg-2" str so ;
      f_str o "arg-3" s2 ;
      f_node o "arg-4" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_WithTra (pl, acts) ->
      node_start o "tp_action.tp_withtra" ;
      f_node o "arg-1" (v_list tp_pe_string) pl ;
      f_node o "arg-2" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_WithVarScope acts ->
      node_start o "tp_action.tp_withvarscope" ;
      v_list tp_action o acts ;
      node_end o
  | Tp.TP_ActionTime (p, acts) ->
      node_start o "tp_action.tp_actiontime" ;
      f_node o "arg-1" tp_pe_string p ;
      f_node o "arg-2" (v_list tp_action) acts ;
      node_end o
  | Tp.TP_RegisterUninstall p ->
      node_start o "tp_action.tp_registeruninstall" ;
      tp_pe_string o p ;
      node_end o)

(* -- tp_patch -- *)

and tp_patch o (p : Tp.tp_patch) =
  line_start o ;
  (match p with
  | Tp.TP_PatchBashFor (pats, pl) ->
      node_start o "tp_patch.tp_patchbashfor" ;
      f_node o "arg-1" (v_list (triple str (v_opt bool) str)) pats ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchClearArray ps ->
      node_start o "tp_patch.tp_patchcleararray" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.TP_PatchDefineArray (ps, sl) ->
      node_start o "tp_patch.tp_patchdefinearray" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" (v_list str) sl ;
      node_end o
  | Tp.TP_DefineAssociativeArray (ps, l) ->
      node_start o "tp_patch.tp_defineassociativearray" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" (v_list (pair (v_list tp_pe_string) tp_pe_string)) l ;
      node_end o
  | Tp.TP_PatchSortArrayIndices (ps, s) ->
      node_start o "tp_patch.tp_patchsortarrayindices" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" array_indices_sort_type s ;
      node_end o
  | Tp.TP_PatchPHPEach (p1, p2, p3, pl) ->
      node_start o "tp_patch.tp_patchphpeach" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_node o "arg-3" tp_pe_string p3 ;
      f_node o "arg-4" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchForEach (ps, sl, pl) ->
      node_start o "tp_patch.tp_patchforeach" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" (v_list str) sl ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchStrRef (e, ts) ->
      node_start o "tp_patch.tp_patchstrref" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tlk_string ts ;
      node_end o
  | Tp.TP_PatchStrRefEvaluated (e, s) ->
      node_start o "tp_patch.tp_patchstrrefevaluated" ;
      f_node o "arg-1" tp_patchexp e ;
      f_str o "arg-2" s ;
      node_end o
  | Tp.TP_PatchString (b1, b2, s, ts) ->
      node_start o "tp_patch.tp_patchstring" ;
      f_opt o "arg-1" bool b1 ;
      f_opt o "arg-2" bool b2 ;
      f_str o "arg-3" s ;
      f_node o "arg-4" tlk_string ts ;
      node_end o
  | Tp.TP_PatchStringTextually (b1, b2, s1, s2, eo) ->
      node_start o "tp_patch.tp_patchstringtextually" ;
      f_opt o "arg-1" bool b1 ;
      f_opt o "arg-2" bool b2 ;
      f_str o "arg-3" s1 ;
      f_str o "arg-4" s2 ;
      f_opt o "arg-5" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchStringEvaluate (b, s, pl, s2) ->
      node_start o "tp_patch.tp_patchstringevaluate" ;
      f_opt o "arg-1" bool b ;
      f_str o "arg-2" s ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      f_str o "arg-4" s2 ;
      node_end o
  | Tp.TP_PatchReplaceBCSBlock (s1, s2, plo, b, bo) ->
      node_start o "tp_patch.tp_patchreplacebcsblock" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_opt o "arg-3" (v_list tp_patch) plo ;
      f_bool o "arg-4" b ;
      f_opt o "arg-5" bool bo ;
      node_end o
  | Tp.TP_PatchReplaceBCSBlockRE (s1, s2, plo) ->
      node_start o "tp_patch.tp_patchreplacebcsblockre" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_opt o "arg-3" (v_list tp_patch) plo ;
      node_end o
  | Tp.TP_PatchApplyBCSPatch (s, so) ->
      node_start o "tp_patch.tp_patchapplybcspatch" ;
      f_str o "arg-1" s ;
      f_opt o "arg-2" str so ;
      node_end o
  | Tp.TP_PatchByte (e1, e2) ->
      node_start o "tp_patch.tp_patchbyte" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PatchShort (e1, e2) ->
      node_start o "tp_patch.tp_patchshort" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PatchLong (e1, e2) ->
      node_start o "tp_patch.tp_patchlong" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PatchGetStrRef (e, ps, b1, b2) ->
      node_start o "tp_patch.tp_patchgetstrref" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      node_end o
  | Tp.TP_PatchReadAscii (e, ps, so, e2, b) ->
      node_start o "tp_patch.tp_patchreadascii" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" str so ;
      f_node o "arg-4" tp_patchexp e2 ;
      f_bool o "arg-5" b ;
      node_end o
  | Tp.TP_PatchReadStrRef (e, ps, so, b1, b2) ->
      node_start o "tp_patch.tp_patchreadstrref" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" str so ;
      f_bool o "arg-4" b1 ;
      f_bool o "arg-5" b2 ;
      node_end o
  | Tp.TP_PatchReadByte (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadbyte" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadSByte (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadsbyte" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadSShort (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadsshort" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadShort (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadshort" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadLong (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadlong" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadSLong (e, ps, eo) ->
      node_start o "tp_patch.tp_patchreadslong" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_opt o "arg-3" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchReadLN ps ->
      node_start o "tp_patch.tp_patchreadln" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.TP_PatchGetOffsetArray (ps, t) ->
      node_start o "tp_patch.tp_patchgetoffsetarray" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2"
          (sept tp_patchexp tp_patchexp tp_patchexp tp_patchexp tp_patchexp
             tp_patchexp tp_patchexp) t ;
      node_end o
  | Tp.TP_PatchGetOffsetArray2 (ps, t) ->
      node_start o "tp_patch.tp_patchgetoffsetarray2" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2"
          (oct tp_patchexp tp_patchexp tp_patchexp tp_patchexp tp_patchexp
             tp_patchexp tp_patchexp tp_patchexp) t ;
      node_end o
  | Tp.TP_Launch_Patch_Macro (s, b) ->
      node_start o "tp_patch.tp_launch_patch_macro" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      node_end o
  | Tp.TP_Launch_Patch_Function (s, b, l1, l2, l3, l4) ->
      node_start o "tp_patch.tp_launch_patch_function" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      f_node o "arg-3" (v_list (pair tp_pe_string tp_patchexp)) l1 ;
      f_node o "arg-4" (v_list (pair tp_pe_string tp_pe_string)) l2 ;
      f_node o "arg-5" (v_list (pair tp_pe_string tp_pe_string)) l3 ;
      f_node o "arg-6" (v_list (pair tp_pe_string tp_pe_string)) l4 ;
      node_end o
  | Tp.TP_Add_Known_Spell (s, e, s2) ->
      node_start o "tp_patch.tp_add_known_spell" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      f_str o "arg-3" s2 ;
      node_end o
  | Tp.TP_Add_Memorized_Spell (s, e, s2, e2) ->
      node_start o "tp_patch.tp_add_memorized_spell" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      f_str o "arg-3" s2 ;
      f_node o "arg-4" tp_patchexp e2 ;
      node_end o
  | Tp.TP_Read2DA (e1, e2, e3, ps) ->
      node_start o "tp_patch.tp_read2da" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      f_node o "arg-4" tp_pe_string ps ;
      node_end o
  | Tp.TP_Read2DANow (s, e) ->
      node_start o "tp_patch.tp_read2danow" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TP_Read2DAFormer (s, e1, e2, s2) ->
      node_start o "tp_patch.tp_read2daformer" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e1 ;
      f_node o "arg-3" tp_patchexp e2 ;
      f_str o "arg-4" s2 ;
      node_end o
  | Tp.TP_Get2DARows (e, ps) ->
      node_start o "tp_patch.tp_get2darows" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      node_end o
  | Tp.TP_Get2DACols ps ->
      node_start o "tp_patch.tp_get2dacols" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.TP_CountRegexpInstances (b1, b2, s, ps) ->
      node_start o "tp_patch.tp_countregexpinstances" ;
      f_opt o "arg-1" bool b1 ;
      f_opt o "arg-2" bool b2 ;
      f_str o "arg-3" s ;
      f_node o "arg-4" tp_pe_string ps ;
      node_end o
  | Tp.TP_PatchPrint ts ->
      node_start o "tp_patch.tp_patchprint" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_PatchLog ts ->
      node_start o "tp_patch.tp_patchlog" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_PatchReraise ->
      node_start o "tp_patch.tp_patchreraise" ; node_end o
  | Tp.TP_PatchFail ts ->
      node_start o "tp_patch.tp_patchfail" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_PatchAbort ts ->
      node_start o "tp_patch.tp_patchabort" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_PatchWarn ts ->
      node_start o "tp_patch.tp_patchwarn" ;
      tlk_string o ts ;
      node_end o
  | Tp.TP_PatchSprint (ps, pt, b) ->
      node_start o "tp_patch.tp_patchsprint" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" tp_pe_tlk pt ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_PatchSprintf (ps, pt, el) ->
      node_start o "tp_patch.tp_patchsprintf" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" tp_pe_tlk pt ;
      f_node o "arg-3" (v_list tp_patchexp) el ;
      node_end o
  | Tp.TP_PatchTextSprint (p1, p2, b) ->
      node_start o "tp_patch.tp_patchtextsprint" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_SourceBiff (p1, p2) ->
      node_start o "tp_patch.tp_sourcebiff" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.TP_PatchSpaces (p1, p2) ->
      node_start o "tp_patch.tp_patchspaces" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.TP_PatchQuote (p1, p2) ->
      node_start o "tp_patch.tp_patchquote" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.TP_PatchToLower ps ->
      node_start o "tp_patch.tp_patchtolower" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.TP_PatchToUpper ps ->
      node_start o "tp_patch.tp_patchtoupper" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.TP_PatchSnprint (e, ps, pt) ->
      node_start o "tp_patch.tp_patchsnprint" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_node o "arg-3" tp_pe_tlk pt ;
      node_end o
  | Tp.TP_PatchASCII (e, ps, b, eo) ->
      node_start o "tp_patch.tp_patchascii" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tp_pe_string ps ;
      f_bool o "arg-3" b ;
      f_opt o "arg-4" tp_patchexp eo ;
      node_end o
  | Tp.TP_PatchASCIITerminated (e, s) ->
      node_start o "tp_patch.tp_patchasciiterminated" ;
      f_node o "arg-1" tp_patchexp e ;
      f_str o "arg-2" s ;
      node_end o
  | Tp.TP_PatchInsertBytes (e1, e2) ->
      node_start o "tp_patch.tp_patchinsertbytes" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PatchDeleteBytes (e1, e2) ->
      node_start o "tp_patch.tp_patchdeletebytes" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PatchSet (ps, e, b) ->
      node_start o "tp_patch.tp_patchset" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" tp_patchexp e ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_PatchSetIdsSymOfInt (s1, s2, e) ->
      node_start o "tp_patch.tp_patchsetidssymofint" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" tp_patchexp e ;
      node_end o
  | Tp.TP_PatchWhile (e, pl) ->
      node_start o "tp_patch.tp_patchwhile" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchFor (pl1, e, pl2, pl3) ->
      node_start o "tp_patch.tp_patchfor" ;
      f_node o "arg-1" (v_list tp_patch) pl1 ;
      f_node o "arg-2" tp_patchexp e ;
      f_node o "arg-3" (v_list tp_patch) pl2 ;
      f_node o "arg-4" (v_list tp_patch) pl3 ;
      node_end o
  | Tp.TP_PatchIf (e, pl1, pl2) ->
      node_start o "tp_patch.tp_patchif" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" (v_list tp_patch) pl1 ;
      f_node o "arg-3" (v_list tp_patch) pl2 ;
      node_end o
  | Tp.TP_PatchTry (pl, l) ->
      node_start o "tp_patch.tp_patchtry" ;
      f_node o "arg-1" (v_list tp_patch) pl ;
      f_node o "arg-2"
          (v_list (triple (v_list tp_patchexp) tp_patchexp (v_list tp_patch))) l ;
      node_end o
  | Tp.TP_PatchMatch (e, l) ->
      node_start o "tp_patch.tp_patchmatch" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2"
          (v_list (triple (v_list tp_patchexp) tp_patchexp (v_list tp_patch))) l ;
      node_end o
  | Tp.TP_PatchReinclude sl ->
      node_start o "tp_patch.tp_patchreinclude" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_PatchInclude sl ->
      node_start o "tp_patch.tp_patchinclude" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_PatchRandomSeed e ->
      node_start o "tp_patch.tp_patchrandomseed" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PatchInnerAction acts ->
      node_start o "tp_patch.tp_patchinneraction" ;
      v_list tp_action o acts ;
      node_end o
  | Tp.TP_PatchInnerBuff (s, pl) ->
      node_start o "tp_patch.tp_patchinnerbuff" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchInnerBuffFile (s, pl) ->
      node_start o "tp_patch.tp_patchinnerbufffile" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchInnerBuffSave (ps, s, pl) ->
      node_start o "tp_patch.tp_patchinnerbuffsave" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_str o "arg-2" s ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchInsert2DARow (e1, e2, e3) ->
      node_start o "tp_patch.tp_patchinsert2darow" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      node_end o
  | Tp.TP_Patch2DA (e1, e2, e3, e4) ->
      node_start o "tp_patch.tp_patch2da" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      f_node o "arg-4" tp_patchexp e4 ;
      node_end o
  | Tp.TP_Patch2DALater (s, e1, e2, e3) ->
      node_start o "tp_patch.tp_patch2dalater" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e1 ;
      f_node o "arg-3" tp_patchexp e2 ;
      f_node o "arg-4" tp_patchexp e3 ;
      node_end o
  | Tp.TP_Patch2DANow (s, e) ->
      node_start o "tp_patch.tp_patch2danow" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TP_Remove_2DA_Row (e1, e2) ->
      node_start o "tp_patch.tp_remove_2da_row" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_PrettyPrint2DA e ->
      node_start o "tp_patch.tp_prettyprint2da" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PatchSilent ->
      node_start o "tp_patch.tp_patchsilent" ; node_end o
  | Tp.TP_PatchVerbose ->
      node_start o "tp_patch.tp_patchverbose" ; node_end o
  | Tp.TP_PatchSavFile (e, b, psl, pl) ->
      node_start o "tp_patch.tp_patchsavfile" ;
      f_node o "arg-1" tp_patchexp e ;
      f_bool o "arg-2" b ;
      f_node o "arg-3" (v_list tp_pe_string) psl ;
      f_node o "arg-4" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_Add_Map_Note m ->
      node_start o "tp_patch.tp_add_map_note" ;
      tp_add_map_note o m ;
      node_end o
  | Tp.TP_Patch_Gam (s1, s2, e1, e2) ->
      node_start o "tp_patch.tp_patch_gam" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      f_node o "arg-3" tp_patchexp e1 ;
      f_node o "arg-4" tp_patchexp e2 ;
      node_end o
  | Tp.TP_Add_Cre_Item c ->
      node_start o "tp_patch.tp_add_cre_item" ;
      tp_add_cre_item o c ;
      node_end o
  | Tp.TP_Replace_Cre_Item c ->
      node_start o "tp_patch.tp_replace_cre_item" ;
      tp_add_cre_item o c ;
      node_end o
  | Tp.TP_Add_S_Item (sa, s, sp, e1, e2, e3, s2, e4, so) ->
      node_start o "tp_patch.tp_add_s_item" ;
      f_node o "arg-1" store_args sa ;
      f_str o "arg-2" s ;
      f_node o "arg-3" tp_store_position sp ;
      f_node o "arg-4" tp_patchexp e1 ;
      f_node o "arg-5" tp_patchexp e2 ;
      f_node o "arg-6" tp_patchexp e3 ;
      f_str o "arg-7" s2 ;
      f_node o "arg-8" tp_patchexp e4 ;
      f_opt o "arg-9" str so ;
      node_end o
  | Tp.TP_Remove_Cre_Item sl ->
      node_start o "tp_patch.tp_remove_cre_item" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Set_BG2_Proficiency (e1, e2) ->
      node_start o "tp_patch.tp_set_bg2_proficiency" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.TP_Remove_Known_Spell sl ->
      node_start o "tp_patch.tp_remove_known_spell" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Remove_Memorized_Spell sl ->
      node_start o "tp_patch.tp_remove_memorized_spell" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Remove_Store_Item sl ->
      node_start o "tp_patch.tp_remove_store_item" ;
      v_list str o sl ;
      node_end o
  | Tp.TP_Remove_Known_Spells ->
      node_start o "tp_patch.tp_remove_known_spells" ; node_end o
  | Tp.TP_Remove_Memorized_Spells ->
      node_start o "tp_patch.tp_remove_memorized_spells" ; node_end o
  | Tp.TP_Remove_Cre_Effects ->
      node_start o "tp_patch.tp_remove_cre_effects" ; node_end o
  | Tp.TP_Remove_Cre_Items ->
      node_start o "tp_patch.tp_remove_cre_items" ; node_end o
  | Tp.TP_Extend_Mos (s, e) ->
      node_start o "tp_patch.tp_extend_mos" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TP_PatchWriteFile (e, s, b) ->
      node_start o "tp_patch.tp_patchwritefile" ;
      f_node o "arg-1" tp_patchexp e ;
      f_str o "arg-2" s ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TP_PatchAppendFile (s, b1, b2) ->
      node_start o "tp_patch.tp_patchappendfile" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b1 ;
      f_bool o "arg-3" b2 ;
      node_end o
  | Tp.TP_CompileBAFtoBCS ->
      node_start o "tp_patch.tp_compilebaftobcs" ; node_end o
  | Tp.TP_CompileBCStoBAF ->
      node_start o "tp_patch.tp_compilebcstobaf" ; node_end o
  | Tp.TP_CompileDtoDLG ->
      node_start o "tp_patch.tp_compiledtodlg" ; node_end o
  | Tp.TP_CompileDLGtoD ->
      node_start o "tp_patch.tp_compiledlgtod" ; node_end o
  | Tp.TP_DecompileAndPatch pl ->
      node_start o "tp_patch.tp_decompileandpatch" ;
      v_list tp_patch o pl ;
      node_end o
  | Tp.TP_RefactorTrigger (p1, p2, b1, b2, so) ->
      node_start o "tp_patch.tp_refactortrigger" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      f_opt o "arg-5" str so ;
      node_end o
  | Tp.TP_EvaluateBuffer ->
      node_start o "tp_patch.tp_evaluatebuffer" ; node_end o
  | Tp.TP_EvaluateBufferSpecial s ->
      node_start o "tp_patch.tp_evaluatebufferspecial" ;
      str o s ;
      node_end o
  | Tp.TP_Decompress (e1, e2, e3, dw) ->
      node_start o "tp_patch.tp_decompress" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      f_node o "arg-4" tp_decompress_where dw ;
      node_end o
  | Tp.TP_Compress (e1, e2, e3, dw) ->
      node_start o "tp_patch.tp_compress" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      f_node o "arg-4" tp_decompress_where dw ;
      node_end o
  | Tp.TP_RebuildCreFile ->
      node_start o "tp_patch.tp_rebuildcrefile" ; node_end o
  | Tp.TP_PatchWithTra (psl, pl) ->
      node_start o "tp_patch.tp_patchwithtra" ;
      f_node o "arg-1" (v_list tp_pe_string) psl ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o
  | Tp.TP_PatchWithVarScope pl ->
      node_start o "tp_patch.tp_patchwithvarscope" ;
      v_list tp_patch o pl ;
      node_end o
  | Tp.TP_PatchTime (ps, pl) ->
      node_start o "tp_patch.tp_patchtime" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" (v_list tp_patch) pl ;
      node_end o)

(* -- tp_patchexp -- *)

and tp_patchexp o (e : Tp.tp_patchexp) =
  line_start o ;
  (match e with
  | Tp.Pred_True ->
      node_start o "tp_patchexp.pred_true" ; node_end o
  | Tp.TP_PE_Byte_At e ->
      node_start o "tp_patchexp.tp_pe_byte_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PE_SByte_At e ->
      node_start o "tp_patchexp.tp_pe_sbyte_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PE_Short_At e ->
      node_start o "tp_patchexp.tp_pe_short_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PE_SShort_At e ->
      node_start o "tp_patchexp.tp_pe_sshort_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PE_Long_At e ->
      node_start o "tp_patchexp.tp_pe_long_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.TP_PE_SLong_At e ->
      node_start o "tp_patchexp.tp_pe_slong_at" ;
      tp_patchexp o e ;
      node_end o
  | Tp.PE_Int32 i ->
      node_start o "tp_patchexp.pe_int32" ;
      i32 o i ;
      node_end o
  | Tp.PE_Int i ->
      node_start o "tp_patchexp.pe_int" ;
      int o i ;
      node_end o
  | Tp.PE_String ps ->
      node_start o "tp_patchexp.pe_string" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_StringEqual (p1, p2, b1, b2) ->
      node_start o "tp_patchexp.pe_stringequal" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_bool o "arg-3" b1 ;
      f_bool o "arg-4" b2 ;
      node_end o
  | Tp.PE_StringRegexp (p1, p2, b) ->
      node_start o "tp_patchexp.pe_stringregexp" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.PE_Not e ->
      node_start o "tp_patchexp.pe_not" ;
      tp_patchexp o e ;
      node_end o
  | Tp.PE_Add (e1, e2) ->
      node_start o "tp_patchexp.pe_add" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Sub (e1, e2) ->
      node_start o "tp_patchexp.pe_sub" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Mul (e1, e2) ->
      node_start o "tp_patchexp.pe_mul" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Div (e1, e2) ->
      node_start o "tp_patchexp.pe_div" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Mod (e1, e2) ->
      node_start o "tp_patchexp.pe_mod" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Exp (e1, e2, e3) ->
      node_start o "tp_patchexp.pe_exp" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      node_end o
  | Tp.PE_Equal (e1, e2) ->
      node_start o "tp_patchexp.pe_equal" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_And (e1, e2) ->
      node_start o "tp_patchexp.pe_and" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Or (e1, e2) ->
      node_start o "tp_patchexp.pe_or" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_GT (e1, e2) ->
      node_start o "tp_patchexp.pe_gt" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_GTE (e1, e2) ->
      node_start o "tp_patchexp.pe_gte" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_LT (e1, e2) ->
      node_start o "tp_patchexp.pe_lt" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_LTE (e1, e2) ->
      node_start o "tp_patchexp.pe_lte" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BAND (e1, e2) ->
      node_start o "tp_patchexp.pe_band" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BOR (e1, e2) ->
      node_start o "tp_patchexp.pe_bor" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BNOT e ->
      node_start o "tp_patchexp.pe_bnot" ;
      tp_patchexp o e ;
      node_end o
  | Tp.PE_BXOR (e1, e2) ->
      node_start o "tp_patchexp.pe_bxor" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BLSL (e1, e2) ->
      node_start o "tp_patchexp.pe_blsl" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BLSR (e1, e2) ->
      node_start o "tp_patchexp.pe_blsr" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_BASR (e1, e2) ->
      node_start o "tp_patchexp.pe_basr" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_ABS e ->
      node_start o "tp_patchexp.pe_abs" ;
      tp_patchexp o e ;
      node_end o
  | Tp.PE_Random (e1, e2) ->
      node_start o "tp_patchexp.pe_random" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      node_end o
  | Tp.PE_Buffer_Length ->
      node_start o "tp_patchexp.pe_buffer_length" ; node_end o
  | Tp.PE_String_Length ps ->
      node_start o "tp_patchexp.pe_string_length" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_Index (b1, bo1, bo2, ps, eo, pso) ->
      node_start o "tp_patchexp.pe_index" ;
      f_bool o "arg-1" b1 ;
      f_opt o "arg-2" bool bo1 ;
      f_opt o "arg-3" bool bo2 ;
      f_node o "arg-4" tp_pe_string ps ;
      f_opt o "arg-5" tp_patchexp eo ;
      f_opt o "arg-6" tp_pe_string pso ;
      node_end o
  | Tp.PE_FileContainsEvaluated (p1, p2) ->
      node_start o "tp_patchexp.pe_filecontainsevaluated" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.PE_ResourceContains (p1, p2) ->
      node_start o "tp_patchexp.pe_resourcecontains" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.PE_If (e1, e2, e3) ->
      node_start o "tp_patchexp.pe_if" ;
      f_node o "arg-1" tp_patchexp e1 ;
      f_node o "arg-2" tp_patchexp e2 ;
      f_node o "arg-3" tp_patchexp e3 ;
      node_end o
  | Tp.PE_ModIsInstalled (s, e) ->
      node_start o "tp_patchexp.pe_modisinstalled" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.PE_IsInstalledAfter (p1, e, p2, e2) ->
      node_start o "tp_patchexp.pe_isinstalledafter" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_patchexp e ;
      f_node o "arg-3" tp_pe_string p2 ;
      f_node o "arg-4" tp_patchexp e2 ;
      node_end o
  | Tp.PE_IdOfLabel (p1, p2) ->
      node_start o "tp_patchexp.pe_idoflabel" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.PE_GameIs (s, b, co) ->
      node_start o "tp_patchexp.pe_gameis" ;
      f_str o "arg-1" s ;
      f_bool o "arg-2" b ;
      f_opt o "arg-3" tp_cache_arg co ;
      node_end o
  | Tp.PE_GameIncludes (s, co) ->
      node_start o "tp_patchexp.pe_gameincludes" ;
      f_str o "arg-1" s ;
      f_opt o "arg-2" tp_cache_arg co ;
      node_end o
  | Tp.PE_VariableIsSet ps ->
      node_start o "tp_patchexp.pe_variableisset" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_VariableIsInArray ac ->
      node_start o "tp_patchexp.pe_variableisinarray" ;
      tp_array_construct o ac ;
      node_end o
  | Tp.PE_IdsOfSymbol (s1, s2) ->
      node_start o "tp_patchexp.pe_idsofsymbol" ;
      f_str o "arg-1" s1 ;
      f_str o "arg-2" s2 ;
      node_end o
  | Tp.PE_StateWhichSays (tso, po, s) ->
      node_start o "tp_patchexp.pe_statewhichsays" ;
      f_opt o "arg-1" tlk_string tso ;
      f_opt o "arg-2" (pair tp_patchexp str) po ;
      f_str o "arg-3" s ;
      node_end o
  | Tp.PE_IsAnInt ps ->
      node_start o "tp_patchexp.pe_isanint" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_IsSilent ->
      node_start o "tp_patchexp.pe_issilent" ; node_end o
  | Tp.PE_TraEntryExists (ps, psl) ->
      node_start o "tp_patchexp.pe_traentryexists" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_node o "arg-2" (v_list tp_pe_string) psl ;
      node_end o
  | Tp.PE_Resolve_Str_Ref ts ->
      node_start o "tp_patchexp.pe_resolve_str_ref" ;
      tlk_string o ts ;
      node_end o
  | Tp.PE_SizeOfFile ps ->
      node_start o "tp_patchexp.pe_sizeoffile" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_NextStrref ->
      node_start o "tp_patchexp.pe_nextstrref" ; node_end o
  | Tp.PE_ValidScriptActions ps ->
      node_start o "tp_patchexp.pe_validscriptactions" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_ValidScriptTriggers ps ->
      node_start o "tp_patchexp.pe_validscripttriggers" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_DefinedAsFunction ps ->
      node_start o "tp_patchexp.pe_definedasfunction" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.PE_DefinedAsInlined ps ->
      node_start o "tp_patchexp.pe_definedasinlined" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_File_MD5 (p1, p2) ->
      node_start o "tp_patchexp.pred_file_md5" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o
  | Tp.Pred_File_Exists ps ->
      node_start o "tp_patchexp.pred_file_exists" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_Directory_Exists ps ->
      node_start o "tp_patchexp.pred_directory_exists" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_File_Is_In_Compressed_Bif ps ->
      node_start o "tp_patchexp.pred_file_is_in_compressed_bif" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_Biff_Is_Compressed ps ->
      node_start o "tp_patchexp.pred_biff_is_compressed" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_File_Exists_In_Game ps ->
      node_start o "tp_patchexp.pred_file_exists_in_game" ;
      tp_pe_string o ps ;
      node_end o
  | Tp.Pred_File_Size (ps, i) ->
      node_start o "tp_patchexp.pred_file_size" ;
      f_node o "arg-1" tp_pe_string ps ;
      f_int o "arg-2" i ;
      node_end o
  | Tp.Pred_File_Contains (p1, p2) ->
      node_start o "tp_patchexp.pred_file_contains" ;
      f_node o "arg-1" tp_pe_string p1 ;
      f_node o "arg-2" tp_pe_string p2 ;
      node_end o)

(* -- tp_flag / tp_mod_flag / records / roots -- *)

let tp_flag o (f : Tp.tp_flag) =
  line_start o ;
  (match f with
  | Tp.Version ts ->
      node_start o "tp_flag.version" ;
      tlk_string o ts ;
      node_end o
  | Tp.Auto_Tra (s, so) ->
      node_start o "tp_flag.auto_tra" ;
      f_str o "arg-1" s ;
      f_opt o "arg-2" str so ;
      node_end o
  | Tp.TP_No_If_Eval () ->
      node_start o "tp_flag.tp_no_if_eval" ; node_end o
  | Tp.Menu_Style s ->
      node_start o "tp_flag.menu_style" ;
      str o s ;
      node_end o
  | Tp.Ask_Every_Component ->
      node_start o "tp_flag.ask_every_component" ; node_end o
  | Tp.Always acts ->
      node_start o "tp_flag.always" ;
      v_list tp_action o acts ;
      node_end o
  | Tp.Define_Action_Macro (s, ld, acts) ->
      node_start o "tp_flag.define_action_macro" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_local_declaration) ld ;
      f_node o "arg-3" (v_list tp_action) acts ;
      node_end o
  | Tp.Define_Patch_Macro (s, ld, pl) ->
      node_start o "tp_flag.define_patch_macro" ;
      f_str o "arg-1" s ;
      f_node o "arg-2" (v_list tp_local_declaration) ld ;
      f_node o "arg-3" (v_list tp_patch) pl ;
      node_end o
  | Tp.Allow_Missing sl ->
      node_start o "tp_flag.allow_missing" ;
      v_list str o sl ;
      node_end o
  | Tp.Script_Style s ->
      node_start o "tp_flag.script_style" ;
      script_style o s ;
      node_end o
  | Tp.Load_Macro sl ->
      node_start o "tp_flag.load_macro" ;
      v_list str o sl ;
      node_end o
  | Tp.Readme sl ->
      node_start o "tp_flag.readme" ;
      v_list str o sl ;
      node_end o
  | Tp.Uninstall_Order sl ->
      node_start o "tp_flag.uninstall_order" ;
      v_list str o sl ;
      node_end o
  | Tp.Quick_Menu (l, il) ->
      node_start o "tp_flag.quick_menu" ;
      f_node o "arg-1" (v_list (pair tlk_string (v_list int))) l ;
      f_node o "arg-2" (v_list int) il ;
      node_end o
  | Tp.Auto_Eval_Strings ->
      node_start o "tp_flag.auto_eval_strings" ; node_end o)

let tp_mod_flag o (m : Tp.tp_mod_flag) =
  line_start o ;
  (match m with
  | Tp.TPM_Deprecated ts ->
      node_start o "tp_mod_flag.tpm_deprecated" ;
      tlk_string o ts ;
      node_end o
  | Tp.TPM_RequireComponent (s, i, ts) ->
      node_start o "tp_mod_flag.tpm_requirecomponent" ;
      f_str o "arg-1" s ;
      f_int o "arg-2" i ;
      f_node o "arg-3" tlk_string ts ;
      node_end o
  | Tp.TPM_ForbidComponent (s, i, ts) ->
      node_start o "tp_mod_flag.tpm_forbidcomponent" ;
      f_str o "arg-1" s ;
      f_int o "arg-2" i ;
      f_node o "arg-3" tlk_string ts ;
      node_end o
  | Tp.TPM_RequirePredicate (e, ts) ->
      node_start o "tp_mod_flag.tpm_requirepredicate" ;
      f_node o "arg-1" tp_patchexp e ;
      f_node o "arg-2" tlk_string ts ;
      node_end o
  | Tp.TPM_SubComponents (ts, e, b) ->
      node_start o "tp_mod_flag.tpm_subcomponents" ;
      f_node o "arg-1" tlk_string ts ;
      f_node o "arg-2" tp_patchexp e ;
      f_bool o "arg-3" b ;
      node_end o
  | Tp.TPM_Designated i ->
      node_start o "tp_mod_flag.tpm_designated" ;
      int o i ;
      node_end o
  | Tp.TPM_NotInLog ->
      node_start o "tp_mod_flag.tpm_notinlog" ; node_end o
  | Tp.TPM_InstallByDefault ->
      node_start o "tp_mod_flag.tpm_installbydefault" ; node_end o
  | Tp.TPM_Group (ts, e) ->
      node_start o "tp_mod_flag.tpm_group" ;
      f_node o "arg-1" tlk_string ts ;
      f_node o "arg-2" tp_patchexp e ;
      node_end o
  | Tp.TPM_Label s ->
      node_start o "tp_mod_flag.tpm_label" ;
      str o s ;
      node_end o
  | Tp.TPM_Metadata s ->
      node_start o "tp_mod_flag.tpm_metadata" ;
      str o s ;
      node_end o)

let tp_lang o (l : Tp.tp_lang) =
  line_start o ;
  node_start o "tp_lang" ;
  f_str o "lang_name" l.Tp.lang_name ;
  f_str o "lang_dir_name" l.Tp.lang_dir_name ;
  f_list o "lang_tra_files" str l.Tp.lang_tra_files ;
  node_end o

let tp_mod o (m : Tp.tp_mod) =
  line_start o ;
  node_start o "tp_mod" ;
  f_node o "mod_name" tlk_string m.Tp.mod_name ;
  f_list o "mod_parts" tp_action m.Tp.mod_parts ;
  f_list o "mod_flags" tp_mod_flag m.Tp.mod_flags ;
  node_end o

let tp_file o (t : Tp.tp_file) =
  line_start o ;
  node_start o "tp_file" ;
  f_str o "tp_filename" t.Tp.tp_filename ;
  f_str o "backup" t.Tp.backup ;
  f_str o "author" t.Tp.author ;
  f_list o "flags" tp_flag t.Tp.flags ;
  f_list o "languages" tp_lang t.Tp.languages ;
  f_list o "module_list" tp_mod t.Tp.module_list ;
  f_bool o "is_auto_eval_string" t.Tp.is_auto_eval_string ;
  node_end o

let tp_action_list o (l : Tp.tp_action list) =
  line_start o ;
  node_start o "tp.tp_action_list" ;
  f_list o "list" tp_action l ;
  node_end o

let tp_patch_list o (l : Tp.tp_patch list) =
  line_start o ;
  node_start o "tp.tp_patch_list" ;
  f_list o "list" tp_patch l ;
  node_end o

(* -- dump entry points -- *)

let dump_tp_file stage source t =
  write_dump "tp2" stage source (fun o -> tp_file o t)

let dump_tp_actions grammar stage source l =
  write_dump grammar stage source (fun o -> tp_action_list o l)

let dump_tp_patches stage source l =
  write_dump "tpp" stage source (fun o -> tp_patch_list o l)
