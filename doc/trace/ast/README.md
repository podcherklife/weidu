# AST Dumping (`--dump-ast`)

WeiDU can dump the AST values produced by its parsers as **typed
S-expressions**, so that they can be compared against a reimplementation
that builds the same structures.  This is the first of the `doc/trace`
feature set: observability tooling for WeiDU's parse/execute pipeline.

## Usage

Add `--dump-ast <directory>` to any normal WeiDU command line.  When
the flag is given, every AST that gets produced by a parser during that
run is written into `<directory>` (created if missing):

- `<source-file>.parse.sexp` — the value **right out of the parser**
  (the parser is treated as a pure producer; instrumentation sits at
  the "parsing just ended" point of every parse wrapper).
- `<source-file>.exec.sexp` — the same value **right before it is
  executed/walked** (after any rewrites or validations, at the entry of
  the executor).

Both stages are always written where both exist.  All dump calls are
purely additive instrumentation: they only read the AST, and any dump
failure is logged as a `WARNING:` and never alters execution.  Running
the same command twice produces byte-identical dumps, so `diff -r`
between two dump directories is meaningful.

### Common invocations

The flag composes with every existing WeiDU flow.  The most useful
ones:

```sh
# Check that a file parses, dumping whatever the parser produced.
# Works for kinds D, BAF, TP2, TPA, TPP (parse dumps only: nothing is
# executed by a parse check).
weidu --nogame --dump-ast dumps --parse-check D mymod.d
weidu --nogame --dump-ast dumps --parse-check BAF mymod.baf

# List components of a mod: parses the TP2 without installing.
weidu --nogame --dump-ast dumps --list-components setup-mymod.tp2 0

# Compile a .d to .dlg (or .baf to .bcs): parse + pre-execution dumps.
weidu --nogame --dump-ast dumps --out outdir mymod.d

# A full installation run: dumps for the TP2 itself (parse and exec),
# every INCLUDE'd .tp2/.tpa library, .tra files, IDS tables, WeiDU.log.
weidu --game <gamedir> --yes --dump-ast dumps setup-mymod.tp2
```

Notes:

- **BAF/BCS need IDS files.** Symbolic identifiers in BAF/BCS text are
  resolved against IDS tables *while parsing*, so a BAF parse requires
  the relevant IDS files — from a game directory, or provided with
  `--search-ids <dir>` (e.g. minimal hand-made `TRIGGER.IDS` /
  `ACTION.IDS`).  This is inherent to WeiDU's parser, not to the dump
  instrumentation; the dump still captures the final AST value.
- **No game required for parsing.** `--nogame` plus `--parse-check`
  (or `--list-components`) exercises the parsers without a game
  installation.
- Passing `--dump-ast` twice just overwrites the directory setting;
  dumps are written per parse, so re-parses overwrite their own files
  with identical content.

### Dump file naming

Dumps are named after the file the AST originated from, plus the stage
suffix: `garock.d.parse.sexp`, `setup-mymod.tp2.exec.sexp`, ...
Values parsed from memory buffers keep whatever name the surrounding
context carries (e.g. resource names like `AR1000.BCS`).  If two
*different* files share a basename, the later one gets a deterministic
suffix derived from a hash of its full path
(e.g. `mymod.tra.1837465927.parse.sexp`), recorded in a registry —
this avoids silent overwrites.  Should a value ever be dumped with no
file name in context, it would be called `anon-<grammar>-<n>.sexp`
(currently unreachable: every instrumented site has a name).

## File format

Each dump file contains a single top-level S-expression:

```lisp
(ast-dump
  (weidu-version "25201")
  (grammar "d")
  (stage "parse")
  (source "../test/good-syntax/jc-ast.d")
  (ast
    (dc.d_file
      (list
        (dc.action.append
          ...)))))
```

Node conventions (every node is `(name children...)`):

| Construct | Rendering |
|---|---|
| Record | `(type_name (field value) ...)` — field names as in `src/*.ml` |
| Variant constructor | `(type_name.constructor args...)`, all lowercase; the type prefix disambiguates same-named constructors |
| Scalar constructor arg | printed inline: `(tp_patchexp.pe_int 42)` |
| Node-valued constructor arg | child node on its own line |
| Multi-arg constructor | positional wrappers `(arg-1 ...)` ... `(arg-N ...)` |
| Tuple (no field names in OCaml) | `(pair ...)/(triple ...)/(quad ...)/(quint ...)/(sext ...)/(sept ...)/(oct ...)` with `(arg-N ...)` children |
| Option | `(field none)` or `(field (some <value>))` |
| List / array | `(field (list <elems>))`; scalar elements inline, node elements one per line |
| Strings | double-quoted; `\` `"` `\n` `\r` `\t` escaped, all other bytes verbatim (non-ASCII text is preserved byte-for-byte for comparison) |
| Integers / Int32 | decimal (`Int32` printed via `Int32.to_string`) |
| Booleans | `true` / `false` |

Every non-scalar node starts on its own line, so diffs localize
structural changes precisely.

## What is instrumented

| Grammar | Parse stage site | Exec stage site |
|---|---|---|
| TP2 (`Tp.tp_file`) | `Parsewrappers.handle_tp2_filename_caching` (after parse; cache hits emit nothing because no parse happens) | `Tpwork.handle_tp` entry |
| TPA (`Tp.tp_action list`) | `Parsewrappers.handle_tph_filename` | `Tpuninstall` right before `handle_al` |
| TPP (`Tp.tp_patch list`) | `Parsewrappers.handle_tpp_filename` | `Tppatch` right before `process_patch2` fold |
| D (`Dc.action list`) | `Parsewrappers.handle_d_filename` / `parse_d_buffer` | `Parsewrappers.emit_dlg_files` / `handle_d_buffer`, right before `Dc.dc` |
| TRA (`(int * Dlg.tlk_string) list` — strref number + text) | `Parsewrappers.get_tra_list_filename` and the direct `Dparser.tra_file` calls in `main.ml` (`--tlkcmp`, `--untraify`, `--traify`) | `Parsewrappers.handle_tra_filename`, right before `Dc.add_trans_strings` |
| BAF (`Bcs.script`) | `Parsewrappers.handle_baf_filename`, `compile_baf_filename`, `handle_script_buffer` | `compile_baf_filename` / `main.ml compile_baf`, right before `Bcs.save_bcs` |
| BCS (`Bcs.script`) | `Parsewrappers.handle_script_buffer` | same point (parse and use are adjacent; see below) |
| IDS (`Ids.ids list`) | `Bcs.get_ids_map` (via hook) | same point, right before `make_ids_map` |
| WeiDU.log (`Dparser.log_file`) | `Parsewrappers.load_log` | — (the parsed value is only transformed into `Tp.the_log`; documented below) |
| Refactor-BAF (`Refactorbaf.trigger list`) | `TP_RefactorTrigger`'s `load_triggers` callback | — (the list is immediately rewritten and re-printed; see below) |

## Deliberate exclusions and known limitations

These parses are *not* dumped, with reasons:

1. **Validation-only parses.** `Parsewrappers.handle_script_al/tl`
   (used by `PE_ValidScriptActions` / `PE_ValidScriptTriggers`) parse a
   buffer solely to check that it parses and then throw the result away.
   There is no AST that gets executed, so there is nothing to compare.
2. **Reprint/formatting round-trips.** `Parsewrappers.reprint_d_action`
   and `Dlg.reprint_trigger` re-parse already-validated trigger/action
   text only to pretty-print it back into a buffer.  These are output
   formatting aids, not parser→executor flows.
3. **Refactor-D parser.** `Refactordparser.d_file` returns a `string`,
   not an AST (it re-prints the refactored text), so there is no AST
   state to dump.  The Refactor-BAF `baf_file` start rule behaves the
   same way; only its `trigger_list` rule produces an AST and is dumped.
4. **TP2 cache hits.** `handle_tp2_filename_caching` returns a cached
   `Tp.tp_file` without re-parsing; the parse-stage dump already exists
   from the first parse, and the AST is not re-derived.

Flow notes:

- **TP2 dual parsers.** A TP2 file is first offered to the ocamlyacc
  parser (`Toldparser`) and, if that fails, to the Elkhound GLR parser
  (`Trealparser`).  Both produce the same `Tp.tp_file` type; the dump
  reflects whichever succeeded.
- **TP2 parse vs. exec.** The top-level `Tp.tp_file` is not rewritten
  between parse and `Tpwork.handle_tp`, so its two dumps are expected
  to be byte-identical apart from the `stage` line — this is a useful
  invariant to check.  TP2 files pulled in via `INCLUDE`/`REINCLUDE`
  get parse dumps only (they supply macro/function definitions to the
  running install; they are never executed as standalone TP2 files).
- **D files.** `.d` actions accumulate in `Dc.d_action_list` across
  files, and the real rewrites (IF_FILE_EXISTS, COPY_TRANS, chain
  processing, ...) happen *inside* `Dc.dc`.  The exec-stage dump
  therefore groups the accumulated list by source file immediately
  before `Dc.dc` — that grouping is the closest well-defined per-file
  "right before execution" point.
- **BCS/BAF buffer parses.** When `handle_script_buffer` parses a
  script (e.g. for `TP_PatchReplaceBCSBlock` or `COMPILE_BAF_TO_BCS`),
  the parsed value is consumed immediately by the caller with no
  intervening rewrite, so the parse dump is also the pre-execution
  state; only the compile paths additionally write an explicit `exec`
  dump at the `Bcs.save_bcs` call.
- **IDS.** Parse and use (`make_ids_map`) are adjacent inside
  `Bcs.get_ids_map`; both dump points fire there.  IDS parsing only
  happens as a side effect of script compilation/decompilation, so IDS
  dumps appear when BAF/BCS flows reference IDS symbols.
- **WeiDU.log / TPA / TPP / Refactor-BAF** have no separate exec-stage
  dump because the parsed value is either immediately transformed into
  another representation (log → `Tp.the_log`, refactor lists →
  substituted text) or executed at the sites listed above.  Where an
  exec dump exists it fires at that site.
- **`--parse-check <kind> <file>`** flows through the same instrumented
  wrappers, so a parse check automatically produces `parse` dumps (and
  no `exec` dumps, since nothing is executed).
- **Bundled libraries.** WeiDU automatically parses its own bundled
  TPA function libraries (`.../WEIDU_NAMESPACE/*.tpa`) during
  installations; these appear as parse dumps too, since they are ASTs
  the executor genuinely consumes.

## Reimplementation notes

A reimplementation should produce structurally identical trees for the
same inputs:

- Constructor nodes are named `type.constructor` in lowercase; a
  reimplementation using the same type names matches directly.
- Positional `arg-N` wrappers appear *only* where a constructor takes
  more than one argument (or where an OCaml tuple has no field names —
  `pair`/`triple`/... nodes); record fields always use their real
  names.
- Serializers use exhaustive matches with no wildcards, so the
  compiler enforces that every constructor of every dumped type is
  handled — adding a constructor to `src/tp.ml` without updating
  `src/astdumpTp.ml` will fail the build rather than silently produce
  incomplete dumps.
- Dump order follows list order in the AST; nothing is sorted or
  canonicalized, so ordering differences are visible in a diff rather
  than hidden.

## Implementation map

For future trace features (and reviewers), the pieces live in:

- `src/astdump.ml` — writer core: configuration (the `--dump-ast`
  flag state), deterministic file naming, the typed S-expression
  emitters, and the top-level `write_dump` entry.
- `src/astdumpBcs.ml`, `src/astdumpDlg.ml`, `src/astdumpTp.ml` —
  per-grammar serializers (BAF/BCS/IDS/Refactorbaf, Dlg/Dc/TRA/log,
  Tp respectively).
- `Depends` — module registration (astdump modules sit after the type
  modules they serialize and before their users).
- Instrumentation call sites are marked with `AST dump` comments and
  listed in the table above.
