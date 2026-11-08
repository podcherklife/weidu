(* AST dump instrumentation.
 *
 * Emits the AST values produced by WeiDU's parsers as typed
 * S-expressions, so they can be compared against a reimplementation.
 *
 * This module is purely additive instrumentation: it is inactive unless
 * the --dump-ast flag supplies a directory, all dumping is wrapped so
 * that failures only produce log warnings, and no dumped value is ever
 * modified.  See doc/trace/ast/README.md for the format specification and
 * the list of instrumented (and excluded) parse sites. *)

open BatteriesInit
open Hashtblinit
open Util

(* The two instrumented points in a parser/executor pipeline. *)
type stage =
  | Parse
  | Exec

let stage_name = function
  | Parse -> "parse"
  | Exec -> "exec"

(* -- configuration -- *)

let dump_dir : string option ref = ref None

let enabled () = !dump_dir <> None

let set_dump_dir dir =
  (try Unix.mkdir dir 0o777 with _ -> ()) ;
  dump_dir := Some dir

(* -- writer -- *)

(* Layout conventions:
 *
 *   - "value serializers" (scalars, option/list bodies, constructor
 *     nodes for AST types) write at the current position; node-valued
 *     ones emit their own line break + indentation first, scalars are
 *     written inline.
 *   - "field/arg serializers" (the f_ helpers) write a named node on its own line,
 *     wrapping either a scalar or a value serializer output. *)

type out = { b : Buffer.t ; mutable ind : int ; mutable sp : bool }

let create_out () = { b = Buffer.create 65536 ; ind = 0 ; sp = false }

let line_start o =
  Buffer.add_char o.b '\n' ;
  Buffer.add_string o.b (String.make (2 * o.ind) ' ') ;
  o.sp <- false

let node_start o name =
  (* separate inline tokens: (name value) / (list "a" "b"); line starts
   * reset the flag, so node children begin cleanly on their own line *)
  if o.sp then Buffer.add_char o.b ' ' ;
  Buffer.add_char o.b '(' ;
  Buffer.add_string o.b name ;
  o.ind <- o.ind + 1 ;
  o.sp <- true

let node_end o =
  Buffer.add_char o.b ')' ;
  o.ind <- o.ind - 1 ;
  o.sp <- true

let atom o s =
  if o.sp then Buffer.add_char o.b ' ' ;
  Buffer.add_string o.b s ;
  o.sp <- true

let str o s =
  if o.sp then Buffer.add_char o.b ' ' ;
  Buffer.add_char o.b '"' ;
  String.iter (fun c ->
    match c with
    | '\\' -> Buffer.add_string o.b "\\\\"
    | '"'  -> Buffer.add_string o.b "\\\""
    | '\n' -> Buffer.add_string o.b "\\n"
    | '\r' -> Buffer.add_string o.b "\\r"
    | '\t' -> Buffer.add_string o.b "\\t"
    | c -> Buffer.add_char o.b c) s ;
  Buffer.add_char o.b '"' ;
  o.sp <- true

let int o i = atom o (string_of_int i)
let i32 o i = atom o (Int32.to_string i)
let bool o b = atom o (if b then "true" else "false")

(* -- bare value bodies (written inline after a node_start) -- *)

let v_opt (f : out -> 'a -> unit) o = function
  | None -> atom o "none"
  | Some v -> node_start o "some" ; f o v ; node_end o

let v_list (f : out -> 'a -> unit) o items =
  node_start o "list" ;
  List.iter (fun x -> f o x) items ;
  node_end o

let v_array (f : out -> 'a -> unit) o a =
  node_start o "list" ;
  Array.iter (fun x -> f o x) a ;
  node_end o

(* -- field/arg nodes (each on its own line) -- *)

let f_str o name s = line_start o ; node_start o name ; str o s ; node_end o
let f_int o name i = line_start o ; node_start o name ; int o i ; node_end o
let f_i32 o name i = line_start o ; node_start o name ; i32 o i ; node_end o
let f_bool o name b = line_start o ; node_start o name ; bool o b ; node_end o
let f_atom o name a = line_start o ; node_start o name ; atom o a ; node_end o

(* f wraps a scalar printer (str/int/...) or a node-valued serializer
 * (which emits its own line_start) or a bare value body (v_opt/v_list). *)
let f_node o name (f : out -> 'a -> unit) v =
  line_start o ; node_start o name ; f o v ; node_end o

let f_opt o name (f : out -> 'a -> unit) v =
  line_start o ; node_start o name ; v_opt f o v ; node_end o

let f_list o name (f : out -> 'a -> unit) items =
  line_start o ; node_start o name ; v_list f o items ; node_end o

let f_array o name (f : out -> 'a -> unit) a =
  line_start o ; node_start o name ; v_array f o a ; node_end o

(* -- anonymous tuples -- *)

(* OCaml tuples carry no field names, so their elements are wrapped in
 * (pair ...)/(triple ...)/... nodes with positional arg-N children. *)

let pair (f : out -> 'a -> unit) (g : out -> 'b -> unit) o (a, b) =
  line_start o ;
  node_start o "pair" ;
  f_node o "arg-1" f a ;
  f_node o "arg-2" g b ;
  node_end o

let triple (f : out -> 'a -> unit) (g : out -> 'b -> unit) (h : out -> 'c -> unit) o (a, b, c) =
  line_start o ;
  node_start o "triple" ;
  f_node o "arg-1" f a ;
  f_node o "arg-2" g b ;
  f_node o "arg-3" h c ;
  node_end o

let quad (f : out -> 'a -> unit) (g : out -> 'b -> unit) (h : out -> 'c -> unit) (i : out -> 'd -> unit) o (a, b, c, d) =
  line_start o ;
  node_start o "quad" ;
  f_node o "arg-1" f a ;
  f_node o "arg-2" g b ;
  f_node o "arg-3" h c ;
  f_node o "arg-4" i d ;
  node_end o

let quint (f : out -> 'a -> unit) (g : out -> 'b -> unit) (h : out -> 'c -> unit) (i : out -> 'd -> unit) (j : out -> 'e -> unit) o (a, b, c, d, e) =
  line_start o ;
  node_start o "quint" ;
  f_node o "arg-1" f a ;
  f_node o "arg-2" g b ;
  f_node o "arg-3" h c ;
  f_node o "arg-4" i d ;
  f_node o "arg-5" j e ;
  node_end o

let sext (f : out -> 'a -> unit) (g : out -> 'b -> unit) (h : out -> 'c -> unit) (i : out -> 'd -> unit) (j : out -> 'e -> unit) (k : out -> 'f -> unit) o (v1, v2, v3, v4, v5, v6) =
  line_start o ;
  node_start o "sext" ;
  f_node o "arg-1" f v1 ;
  f_node o "arg-2" g v2 ;
  f_node o "arg-3" h v3 ;
  f_node o "arg-4" i v4 ;
  f_node o "arg-5" j v5 ;
  f_node o "arg-6" k v6 ;
  node_end o

let sept (f1 : out -> 'a -> unit) (f2 : out -> 'b -> unit) (f3 : out -> 'c -> unit) (f4 : out -> 'd -> unit) (f5 : out -> 'e -> unit) (f6 : out -> 'f -> unit) (f7 : out -> 'g -> unit) o (v1, v2, v3, v4, v5, v6, v7) =
  line_start o ;
  node_start o "sept" ;
  f_node o "arg-1" f1 v1 ;
  f_node o "arg-2" f2 v2 ;
  f_node o "arg-3" f3 v3 ;
  f_node o "arg-4" f4 v4 ;
  f_node o "arg-5" f5 v5 ;
  f_node o "arg-6" f6 v6 ;
  f_node o "arg-7" f7 v7 ;
  node_end o

let oct (f1 : out -> 'a -> unit) (f2 : out -> 'b -> unit) (f3 : out -> 'c -> unit) (f4 : out -> 'd -> unit) (f5 : out -> 'e -> unit) (f6 : out -> 'f -> unit) (f7 : out -> 'g -> unit) (f8 : out -> 'h -> unit) o (v1, v2, v3, v4, v5, v6, v7, v8) =
  line_start o ;
  node_start o "oct" ;
  f_node o "arg-1" f1 v1 ;
  f_node o "arg-2" f2 v2 ;
  f_node o "arg-3" f3 v3 ;
  f_node o "arg-4" f4 v4 ;
  f_node o "arg-5" f5 v5 ;
  f_node o "arg-6" f6 v6 ;
  f_node o "arg-7" f7 v7 ;
  f_node o "arg-8" f8 v8 ;
  node_end o

(* -- file naming -- *)

(* Maps lowercased basenames to the full source path that first claimed
 * them, so that two different files with the same basename get distinct
 * dump names instead of silently overwriting each other. *)
let name_registry : (string, string) Hashtbl.t = Hashtbl.create 17

(* Counter for values parsed from buffers with no file name in context. *)
let anon_counter = ref 0

let dump_filename source grammar stage =
  let suffix = "." ^ stage_name stage ^ ".sexp" in
  if source = "" then begin
    incr anon_counter ;
    Printf.sprintf "anon-%s-%d%s" grammar !anon_counter suffix
  end else begin
    let base = Case_ins.filename_basename source in
    let key = String.lowercase base in
    match (try Some (Hashtbl.find name_registry key) with Not_found -> None) with
    | Some prev when prev <> source ->
        (* Same basename from a different path: disambiguate with a
         * deterministic hash of the full source path. *)
        Printf.sprintf "%s.%d%s" base (abs (Hashtbl.hash source)) suffix
    | _ ->
        Hashtbl.replace name_registry key source ;
        base ^ suffix
  end

(* -- top-level dump -- *)

(* payload must write the ast value at the current position (i.e. a
 * node-valued serializer that emits its own line_start) inside the
 * enclosing (ast ...) node. *)
let write_dump grammar stage source (payload : out -> unit) =
  match !dump_dir with
  | None -> ()
  | Some dir ->
      (try
        let o = create_out () in
        node_start o "ast-dump" ;
        f_str o "weidu-version" Version.version ;
        f_atom o "grammar" grammar ;
        f_atom o "stage" (stage_name stage) ;
        f_str o "source" source ;
        f_node o "ast" (fun o () -> payload o) () ;
        node_end o ;
        Buffer.add_char o.b '\n' ;
        let path = dir ^ "/" ^ dump_filename source grammar stage in
        let oc = Case_ins.perv_open_out path in
        Buffer.output_buffer oc o.b ;
        close_out oc
      with e ->
        log_and_print "WARNING: AST dump of [%s] (%s/%s) failed: %s\n"
          source grammar (stage_name stage) (printexc_to_string e))
