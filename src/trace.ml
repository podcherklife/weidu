(* Execution trace instrumentation.

   Records the filesystem operations (reads, writes, deletes, renames) and
   external command executions of a run as JSONL events, so they can be
   compared against a reimplementation.  Companion to the AST dumping of
   Astdump (--dump-ast), which observes the parse/execute pipeline; see
   doc/trace/execution/README.md for the event schema and the list of
   instrumented (and excluded) sites.

   This module is purely additive instrumentation: it is inactive unless the
   --trace flag supplies a path, event failures disable the trace instead of
   aborting the run, and no traced operation is ever modified.

   It deliberately has no project dependencies.  It must be usable from the
   low-level filesystem layer (Case_ins) as well as from Util/Load.  It
   therefore uses raw OCaml I/O for its own output channel and must never be
   routed through Util.open_for_writing or Case_ins.perv_open_out, which
   keeps the trace file outside the traced operations. *)

type value =
  | VString of string
  | VInt of int
  | VInt64 of int64
  | VBool of bool
  | VFloat of float
  | VNull
  | VArray of value list

let enabled = ref false
let channel = ref (None : out_channel option)
let next_seq = ref 0
let trace_path = ref ""
let suppress_file_read_count = ref 0

let escape_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"' ;
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | '\b' -> Buffer.add_string b "\\b"
    | '\012' -> Buffer.add_string b "\\f"
    | c when Char.code c < 32 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) s ;
  Buffer.add_char b '"' ;
  Buffer.contents b

let rec value_to_json = function
  | VString s -> escape_string s
  | VInt i -> string_of_int i
  | VInt64 i -> Int64.to_string i
  | VBool b -> string_of_bool b
  | VFloat f -> Printf.sprintf "%.6f" f
  | VNull -> "null"
  | VArray l ->
      "[" ^ String.concat "," (List.map value_to_json l) ^ "]"

let emit event fields =
  if !enabled then
    match !channel with
    | None -> ()
    | Some ch ->
        incr next_seq ;
        let b = Buffer.create 256 in
        Buffer.add_string b "{\"ts\":" ;
        Buffer.add_string b (Printf.sprintf "%.6f" (Unix.gettimeofday ())) ;
        Buffer.add_string b ",\"seq\":" ;
        Buffer.add_string b (string_of_int !next_seq) ;
        Buffer.add_string b ",\"event\":" ;
        Buffer.add_string b (escape_string event) ;
        List.iter (fun (k, v) ->
          Buffer.add_char b ',' ;
          Buffer.add_string b (escape_string k) ;
          Buffer.add_char b ':' ;
          Buffer.add_string b (value_to_json v)) fields ;
        Buffer.add_string b "}\n" ;
        (try
          output_string ch (Buffer.contents b) ;
          flush ch
        with e ->
          enabled := false ;
          channel := None ;
          (try close_out ch with _ -> ()) ;
          prerr_endline
            ("WARNING: filesystem trace disabled: " ^ Printexc.to_string e))

let close () =
  if !enabled then begin
    emit "trace_end" [] ;
    match !channel with
    | None -> ()
    | Some ch ->
        (try flush ch with _ -> ()) ;
        (try close_out ch with _ -> ()) ;
        channel := None ;
        enabled := false
  end

let init path =
  if !enabled then close () ;
  trace_path := path ;
  (* Mirror Astdump.set_dump_dir: create the parent directory if missing
   * (single level, failures ignored -- the open below reports them). *)
  (try
    let dir = Filename.dirname path in
    if dir <> "." && dir <> "" && not (Sys.file_exists dir) then
      Unix.mkdir dir 0o777
  with _ -> ()) ;
  try
    let ch = open_out_bin path in
    channel := Some ch ;
    enabled := true ;
    at_exit close
  with e ->
    prerr_endline
      ("WARNING: unable to open trace file [" ^ path ^ "]: " ^
       Printexc.to_string e)

let s v = VString v
let i v = VInt v
let i64 v = VInt64 v
let b v = VBool v
let null = VNull

let run_start ~version ~argv ~cwd =
  emit "run_start" [
    "schema", s "weidu-fs-trace-v1" ;
    "version", s version ;
    "cwd", s cwd ;
    "argv", VArray (List.map (fun x -> s x) argv) ;
    "pid", i (Unix.getpid ()) ;
    "trace_path", s !trace_path ;
  ]

let without_file_read f =
  incr suppress_file_read_count ;
  try
    let result = f () in
    decr suppress_file_read_count ;
    result
  with e ->
    decr suppress_file_read_count ;
    raise e

let file_read ?(source = "direct") ?(detail = "") path bytes =
  if !suppress_file_read_count = 0 then
    emit "file_read" [
      "path", s path ;
      "bytes", i bytes ;
      "source", s source ;
      "detail", s detail ;
    ]

let file_write_open ?(binary = false) ?(backup = false) path =
  emit "file_write_open" [
    "path", s path ;
    "bytes", null ;
    "binary", b binary ;
    "backup", b backup ;
  ]

let file_write ?(kind = "write") ?(detail = "") ?(backup = false) path bytes =
  emit "file_write" [
    "path", s path ;
    "bytes", i bytes ;
    "kind", s kind ;
    "detail", s detail ;
    "backup", b backup ;
  ]

let file_copy ?(reason = "") src dst bytes =
  emit "file_copy" [
    "src", s src ;
    "dst", s dst ;
    "bytes", i64 bytes ;
    "reason", s reason ;
  ]

let file_delete ?(kind = "file") ?(backup = false) ?bytes path =
  let bytes = match bytes with Some b -> i64 b | None -> null in
  emit "file_delete" [
    "path", s path ;
    "kind", s kind ;
    "bytes", bytes ;
    "backup", b backup ;
  ]

let file_move ?(backup = false) ?bytes src dst =
  let bytes = match bytes with Some b -> i64 b | None -> null in
  emit "file_move" [
    "src", s src ;
    "dst", s dst ;
    "bytes", bytes ;
    "backup", b backup ;
  ]

let process_status_name = function
  | Unix.WEXITED _ -> "exited"
  | Unix.WSIGNALED _ -> "signaled"
  | Unix.WSTOPPED _ -> "stopped"

let process_status_code = function
  | Unix.WEXITED i
  | Unix.WSIGNALED i
  | Unix.WSTOPPED i -> i

let current_dir () =
  try Sys.getcwd () with _ -> ""

let external_exec_fields ~command ~exact = [
  "command", s command ;
  "exact", b exact ;
  "cwd", s (current_dir ()) ;
]

let external_exec_start ~command ~exact =
  if !enabled then
    emit "external_exec_start" (external_exec_fields ~command ~exact)

let external_exec_end ~command ~exact status =
  if !enabled then
    emit "external_exec_end" (
      external_exec_fields ~command ~exact @ [
        "status", s (process_status_name status) ;
        "status_code", i (process_status_code status) ;
      ])

let external_exec_failed ~command ~exact error =
  if !enabled then
    emit "external_exec_end" (
      external_exec_fields ~command ~exact @ [
        "status", s "error" ;
        "status_code", null ;
        "error", s error ;
      ])

let resource_read ~for_what ~name ~ext ~source ~path ~bytes
    ?bif ?bif_index ?tis_index ?offset ?container_size ?compressed () =
  let fields = [
    "for_what", s for_what ;
    "name", s name ;
    "ext", s ext ;
    "source", s source ;
    "path", s path ;
    "bytes", i bytes ;
  ] in
  let fields = match bif with Some v -> fields @ ["bif", s v] | None -> fields in
  let fields = match bif_index with Some v -> fields @ ["bif_index", i v] | None -> fields in
  let fields = match tis_index with Some v -> fields @ ["tis_index", i v] | None -> fields in
  let fields = match offset with Some v -> fields @ ["offset", i v] | None -> fields in
  let fields = match container_size with Some v -> fields @ ["container_size", i v] | None -> fields in
  let fields = match compressed with Some v -> fields @ ["compressed", b v] | None -> fields in
  emit "resource_read" fields
