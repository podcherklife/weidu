# Architecture drilldown: how WeiDU installs a mod

This document is a logical drilldown of WeiDU's execution: the temporal
phases of a mod installation, the sub-steps inside each phase, and the
data-level dependencies between the phases.  It is deliberately not
function-level: calls with the same semantics are grouped, and the focus
is on *when* things happen and *what* each phase consumes and produces.

It complements the two trace features of `doc/trace`:

- `doc/trace/ast` (`--trace ast`) observes the parse/execute pipeline of
  every parsed file — this document explains the pipeline those dumps sit
  inside, and where each "Parse" vs "Exec" dump fires.
- `doc/trace/execution` (`--trace fs`) observes what a run *does* to the
  filesystem — this document explains which phase performs each kind of
  write and why some writes are deferred to the end of the run.

## Notation

- **PARSE** — text or binary → AST / in-memory structure.
- **WALK** — AST → effects: registrations, variable mutations, file
  writes.  The observable parse/walk boundary is exactly where the
  `Astdump.Exec` dumps fire (see [the last section](#parse-vs-exec-where-the-walk-begins)).
- **SERIALIZE** — AST → text or binary written to disk.

WeiDU is not one language.  It is a host family (TP2, TPA/TPH, TPP)
that *embeds* several game-format sublanguages (D, BAF/BCS, TRA, IDS,
2DA) and manipulates two binary game containers (KEY, TLK) plus the
binary DLG format.  Each family has its own lexer/parser, its own AST,
and its own parse/walk/serialize timing; the
[sublanguage lifecycle table](#sublanguage-lifecycle-table) is the
per-family reference, while the phases below are the temporal narrative.

A one-line shape of the run:

> CLI parse → game context load → TP2 parse → per-TP2 interactive
> component loop (each answered component executes *immediately*) →
> deferred flushes (TLK, log) → exit.  Uninstall is the same skeleton
> with "U" answers and a replay of per-component backup bookkeeping
> instead of action execution.

## Phase 0 — Startup and CLI dispatch

Entry point is `main ()` at the end of `src/main.ml`; all non-install
modes branch off the argument processing and exit early.

1. `argv[0]` basename fingerprinting → auto-TP2 name discovery
   (`SETUP-foo.exe` → `SETUP-foo.TP2` candidates in the mod folder or
   cwd).  This is argv-based candidate enumeration, not directory
   globbing.
2. Argument-table parse; positional arguments are classified by
   extension: `.TP2` → install queue, `.TRA` → translation list,
   `.D/.BAF/.BCS/.DLG` → one-shot compile/decompile tools, a bare
   number → DLG state dump.
3. **One-shot tool modes** (`--traify`, `--cmp-*`, D/BAF
   compile/decompile, `--parse-check`, `--list-components`, ...) run
   their own PARSE→WALK/SERIALIZE cycle for one file and exit.  They use
   the same parser entry points as install; `--parse-check` dispatches
   purely by extension (`TP2`/`TPA`/`TPP`/`D`/`BAF`/`DLG`...).

Dependencies: command line only.  Produces: flag refs, the TP2 queue.

## Phase 1 — Game context load (`src/load.ml`)

Everything here reads the *game* directory and produces the single
global context record (`Load.game`) used by every later phase.

1. Game-dir scan (`--game` paths, registry paths, cwd); fatal if no
   `chitin.key` anywhere.
2. **PARSE KEY**: `chitin.key` → `Key.key` (biff array + resource array
   + `resfind` hashtable mapping name,ext → bif/offset), once, in
   `src/key.ml`.  Read-only for the rest of a normal install — `override/`
   shadows biffs, so plain COPY/EXTEND never touch the key.
3. **PARSE TLK (lazy)**: `dialog.tlk`/`dialogf.tlk` located (Enhanced
   Editions: one pair per `lang/*` directory), initially as *null*
   placeholder pairs; the active pair is materialized — real parse →
   `tlk_string` array + `dialog_search` hashtable (text → strref) — only
   after `weidu.conf` and EE-language resolution, still **before any TP2
   parse** (`Tlk.load_tlk`, `src/tlk.ml`).
4. Game-type autodetection (resource probes) → `game_type`,
   `script_style`; `override/` created; game variables seeded.

## Phase 2 — TP2 queue processing (`src/parsewrappers.ml`)

1. **PARSE TP2**: every queued `.tp2` is parsed *whole, in one shot,
   before any UI*.  Fast-path ocamlyacc parser (`toldparser.mly`) first,
   Elkhound GLR fallback (`trealparser`) on any exception — both build
   `Tp.tp_file` values directly, no intermediate parse tree
   (`src/tp.ml`: flags, languages, `module_list` of components; each
   component's `mod_parts` is a `tp_action` list).  Memoized in
   `tp2_cache`; consumed later by the `ID_OF_LABEL` patch expression and
   by uninstall re-parses.
2. **PARSE WeiDU.log**: `Dparser.log_file` → `the_log` (tp2, lang,
   component, name, status) — the install-state source of truth
   (`src/parsewrappers.ml`, `load_log`).

Not parsed yet: every `INCLUDE` library, `.tra`, `.d` and `.baf` source
— everything nested inside the TP2 is deferred to evaluation time.

## Phase 3 — Per-TP2 setup (`Tpwork.handle_tp`, `src/tpwork.ml`)

1. **PARSE TRA + WALK**: language selection (auto if ≤1 language, else
   `--language`, else interactive prompt), then `lang_init` loads the
   chosen `LANGUAGE`'s `.tra` files and merges them onto the
   `Dc.trans_strings` stack — the `@N` namespace, scoped per component
   (`src/dc.ml`).  Sets `%LANGUAGE%`.
2. TP2 metadata variables (`%TP2_AUTHOR%`, `%MOD_VERSION%` from flags).
3. Installed-state check: components vs `the_log` → per-component
   default decisions (Install / Uninstall / Skip / Ask) from
   `INSTALL_BY_DEFAULT`, `--yes`, `--reinstall`, `--force-*` lists.
4. `REQUIRE_*`/`FORBID_*` predicate pre-evaluation (file existence,
   `GAME_IS`, `ID_OF_LABEL`, ...) can flip defaults to Skip.  Predicates
   may trigger secondary **PARSE TP2** runs of *other* mods (through the
   cache) and resource loads through the key.

Produces: the decision array and the language/`@N` context.

## Phase 4 — Component loop (menu ⇒ immediate execution)

Key semantic: **answering a component runs it immediately** — there is
no collect-then-batch pass; the menu loop and the installer are the same
loop.

Per installed component, in order:

1. Reinstall → the previously installed version is uninstalled first.
2. Backup bookkeeping initialized: `set_backup_dir` → `weidu/<n>/`
   (from the TP2 `BACKUP` header) plus the per-component bookkeeping
   files `UNINSTALL.<n>`, `MAPPINGS.<n>`, `MOVE.<n>`, `OTHER.<n>`,
   `ARGS.<n>`, `READLN.<n>`, `UNSETSTR.<n>`, `TLKPATH.<n>`
   (`src/util.ml`, `src/tpwork.ml`).
3. **PARSE TPA + WALK**: `TP_Include Tph.builtin_definitions` — the
   builtin stdlib (`src/tph/define/*.tpa`, `src/tph/include/*.tpa`,
   embedded into the binary at build time, pseudo-namespace
   `.../WEIDU_NAMESPACE/`).  Parsed once per process (memoized in
   `loaded_tph`), then every parsed action is immediately walked via
   `process_action`, so `DEFINE_ACTION_FUNCTION/MACRO` bodies land in
   `Tpstate.functions`/`Tpstate.macros` (`src/tpaction.ml`).
4. **WALK TP2**: `tp.flags` — `ALWAYS` actions run once per component
   install, before the component body; `DEFINE_*_MACRO` flags register.
5. **WALK TP2**: the component body (`mod_parts`) — Phase 5.
6. Success → `(TP2, lang, comp#, name, Installed)` appended to
   `the_log` (unless `NOTINLOG`).  Any exception → `rollback_component`
   replays the backup bookkeeping and the run continues or aborts
   depending on flags; failure sets a nonzero exit code.
7. With `--safe-exit`, `WeiDU.log` is also checkpointed right after the
   component starts.

## Phase 5 — Action interpretation (`Tpaction.process_action_real`)

One recursive interpreter covers ~90 action kinds
(`src/tpaction.ml`).  Structural trick: `OUTER_*`, `IF`, `WHILE` and
friends delegate into the patch engine with an empty buffer, so
`Tppatch.process_patch2` (`buff → buff'`, `src/tppatch.ml`) is the
single evaluation core, re-entered by `TP_PatchInnerAction`.

Environment: `Var` hashtables keyed `"%NAME%"` plus arrays and a scope
stack (`var_push`/`var_pop` per function call, `src/var.ml`);
functions/macros stored as patch-node bodies in `Tpstate.functions` /
`Tpstate.macros` and invoked by rebinding arguments around a fresh
scope.  `%var%` substitution happens *at every string evaluation*
(`Var.get_string_special`, regexp `%[^%]+%`) — the expression family
has no separate parser; it is part of the TP2/TPA/TPP AST and is
evaluated by `Tppe.eval_pe` (`src/tppe.ml`).

By family, with their data dependencies:

- **Variables / control flow** — mutate `Var` only; no file I/O, no
  language events.
- **`INCLUDE` / `PATCH_INCLUDE`** — **PARSE TPA** (action start rule)
  then walk immediately via `process_action`; **PARSE TPP** (patch
  start rule) then fold immediately over the current buffer via
  `process_patch2`.  Separate memo tables (`loaded_tph` vs
  `loaded_tpp`); `REINCLUDE` bypasses the cache.  Exec-time AST dumps
  fire right before the walk.
- **COPY family** — locate the source (direct path, or
  override → key → biff extraction via `Load.load_resource` /
  `Biff.extract_file`), read the whole file into a string buffer, set
  `%SOURCE_*%`/`%DEST_*%`, evaluate constraints
  (`BUT_ONLY_IF_IT_CHANGES` diffs against the original buffer), run the
  read-only patch pre-pass (`process_patch1`), then the buffer
  transform (`process_patch2`), then write via `open_for_writing` —
  which backs up an existing file into `weidu/<n>/` and appends to
  `UNINSTALL.<n>`/`MAPPINGS.<n>` first.  COPY writes may be deferred to
  the end of the action list (`copy_at_end`); `COPY_LARGE` streams in
  chunks.  **2DA** has no parser: the 2DA patch ops are textual with
  column awareness; `PRETTY_PRINT_2DA` delegates to the embedded
  `tb#pretty_print.tpp` (a TPP program walking a 2DA buffer).
- **EXTEND_TOP/BOTTOM** — **PARSE BAF or BCS** for both the extension
  source and the destination script (extension-dispatched: `.BAF` →
  Bafparser, anything else → Bcsparser; `handle_script_buffer`),
  concatenate ASTs, **SERIALIZE** → `Bcs.save_bcs` into `override/`.
- **COMPILE** — per file, in order: `USING`/`LOAD_TRA`/`AUTO_TRA`
  (**PARSE TRA** + WALK into the `@N` namespace), optional
  `EVALUATE_BUFFER` (**%var% substitution applied to the source *text*
  before it is parsed**), then by extension:
  - `.BAF` → **PARSE** (Bafparser → `Bcs.script`) → **SERIALIZE**
    (`Bcs.save_bcs` → `override/*.bcs`), immediate per file.
  - `.D` → **PARSE** (Dparser → `Dc.action list`) → *queued* into
    `Dc.d_action_list` (not walked yet).  At the **end of the COMPILE
    action**: **WALK** = `Dc.dc` over all queued actions
    (`emit_dlg_files`, `src/parsewrappers.ml`) — existing game `.dlg`
    files are **PARSE**d binary→AST on demand (`Dc.make_available`,
    `Dlg.load_dlg`), `COPY_TRANS` is resolved, then **SERIALIZE DLG**
    per touched dialog into `override/`.
  - `@N` resolution timing: inside COMPILE/EXTEND,
    `ok_to_resolve_strings_while_loading` is set, so `@N` resolves at
    D-*parse* time against the `trans_strings` stack; outside that
    window it defers to `resolve_strings` at the Dc postprocess step
    (`src/dc.ml`).
- **IDS** — **PARSE**d lazily whenever a BCS/D compile or a patch op
  needs symbol→int (`Bcs.get_ids_map`, `src/bcs.ml`; idslexer/idsparser,
  cached; the cache is invalidated by `APPEND` to an `.ids`).  Never
  walked beyond symbol resolution.
- **TLK strings** — `SAY`/strref writes enqueue into
  `Dc.strings_to_add` (deduplicated via `dialog_search`); `STRING_SET`
  mutates tlk entries in memory immediately with undo recorded in
  `UNSETSTR.<n>`.  **No tlk serialization here** — see Phase 6.
- **MAKE_BIFF / DISABLE_FROM_KEY** — the only **SERIALIZE KEY** events:
  `chitin.key` is rewritten immediately and re-loaded into `game`
  (`Key.save_key`, `src/key.ml`).  New biffs only happen when a mod
  explicitly asks; the default install path adds files to `override/`.
- **Decompile/patch cycles** (`DECOMPILE_AND_PATCH`,
  `REPLACE_BCS_BLOCK`) — a full round-trip through another sublanguage
  inside one patch op: PARSE BCS → (BAF text) → Bafparser, or
  DLG → (D text) → Dparser; run the patch list on the text; recompile
  back.

## Phase 6 — Run wrap-up (`src/main.ml` tail)

1. Bookkeeping channels closed; **SERIALIZE TLK**: `Dc.strings_to_add`
   flushed → appended to the tlk arrays, `dialog_search` rebuilt, and
   every modified tlk pair written via `Tlk.save_tlk` — the run's
   biggest deferred write.
2. Reinstall of temporarily-uninstalled components (uninstall-stack
   leftovers) — full Phase 4/5 cycles replayed.
3. **WRITE WeiDU.log** — once per TP2 file, at the end of its
   `handle_tp`; `sprintf_log` may re-PARSE logged TP2s and their tras to
   render component names unless `--quick-log`
   (`src/tpstate.ml`).
4. `AT_INTERACTIVE_EXIT` / queued at-exit commands run during process
   exit; exit codes distinguish success, argument warnings, parse
   errors, install failure, etc.  (`src/util.ml`).

## Phase 7 — Uninstall (differences only)

Same skeleton until the component loop; a "U" answer (or `--uninstall`,
or `UNINSTALL` in an `AT_EXIT` chain) runs `Tpuninstall.uninstall`
(`src/tpuninstall.ml`):

1. **Re-PARSE TP2** (cache hit) to get component metadata.
2. Walk `the_log` newest → oldest; any *newer* installed component hit
   on the way is temporarily uninstalled (stack uninstall, marked
   `Temporarily_Uninstalled`, reinstalled at the end of the run) until
   the target is reached, leaving older entries untouched.
3. Consume the per-component backup dir `weidu/<n>/` in
   `UNINSTALL_ORDER`-defined order: `MOVE.<n>` replayed reversed,
   `MAPPINGS.<n>`/`UNINSTALL.<n>` restore originals or delete,
   `OTHER.<n>` deletes created files, `UNSETSTR.<n>`/`TLKPATH.<n>`
   revert tlk edits.
4. `handle_at_uninstall` re-walks `tp.flags` + `mod_parts` executing
   only `AT_*UNINSTALL*`, `TP_If`, `TP_Biff`, `TP_Include` — which may
   PARSE+WALK TPA again.
5. Log entries are flipped (`Permanently_Uninstalled`), never appended.

## Pipeline diagram

```text
argv ──▶ flags + TP2 queue
          ▼
game dir ─▶ chitin.key ─▶ Key.key(resfind)          dialog.tlk ─▶ tlk arrays + dialog_search
          ▼
TP2 text ─▶ parser ─▶ Tp.tp_file AST      WeiDU.log ─▶ the_log
          ▼
language ─▶ .tra ─▶ @N namespace (trans_strings)
          ▼
component loop ── per component:
   backup dir ─▶ ALWAYS ─▶ mod_parts ─▶ process_action_real
                                          ├─ Var env (%vars%, functions/macros)
                                          ├─ COPY + patches ──▶ file writes + backup bookkeeping (immediate)
                                          ├─ COMPILE baf/d ───▶ .bcs (immediate) / .dlg (deferred to Dc.dc)
                                          └─ SAY/STRING_SET ──▶ tlk in memory (flushed end of run)
          ▼
wrap-up: flush tlk ─▶ save tlk ─▶ WeiDU.log ─▶ at-exit ─▶ exit code
```

## Data-dependency map (core artifacts)

| Artifact | Created | Consumed by | Written back |
|---|---|---|---|
| `Key.key` + `resfind` | Phase 1 | `COPY_EXISTING`, predicates, biff ops | only `MAKE_BIFF`/`DISABLE_FROM_KEY` (immediately) |
| tlk arrays + `dialog_search` | Phase 1 (active pair) | `SAY`/`@N` resolution, `STRING_SET` | end of run (`Tlk.save_tlk`) |
| `Dc.strings_to_add` queue | Phase 5 | end-of-run tlk append | end of run |
| `Dc.trans_strings` stack | Phase 3 (`.tra`) | `@N` resolution | never (scoped, discarded) |
| `Var` hashtables + scope stack | Phase 5 | everything (`%var%` substitution) | never; `ARGS.<n>` persisted for args |
| `Tp.tp_file` AST + `tp2_cache` | Phase 2 | Phases 3–7 | never (dump only) |
| `Dc.available_dlgs` / `d_action_list` | Phase 5 | `Dc.dc` → `.dlg` writes | per COMPILE / component end |
| IDS symbol caches | on demand (Phase 5) | BCS/D compile, symbol patch ops | never (invalidated by `APPEND`) |
| `weidu/<n>/` bookkeeping files | Phase 4 | rollback + uninstall | immediately, per operation |
| `the_log` | Phase 2 / Phase 4 appends | menu defaults, uninstall ordering | `WeiDU.log`, per TP2 file |

## Sublanguage lifecycle table

| Family | Parser entry | AST type | PARSE when | WALK when | SERIALIZE when |
|---|---|---|---|---|---|
| **TP2** | `Tparser.parse_tp2_file` (toldparser → GLR fallback) | `Tp.tp_file` | Phase 2 (up-front); `ID_OF_LABEL`; uninstall re-parse; `AT_EXIT` chains; `--parse-check` | setup walk (flags/languages) + per-component `mod_parts` | never (dump only) |
| **TPA/TPH** | `parse_tpa_file` (`handle_tph_filename`) | `tp_action list` | `INCLUDE`/`REINCLUDE` — lazy, memoized; builtin stdlib per component | immediately after parse (`process_action`) → registers functions/macros | never |
| **TPP** | `parse_tpp_file` (`handle_tpp_filename`) | `tp_patch list` | `PATCH_INCLUDE` — lazy, memoized separately | immediately, folded over the current buffer | never |
| **Expressions** (`%var%`, `EVAL`, `$arr$`) | none — AST-embedded | `tp_patchexp` / `tp_pe_string` | (born inside TP2/TPA/TPP parse) | at every eval point (`Tppe.eval_pe`, `Var.get_string_special`) | n/a |
| **TRA** | `Dparser.tra_file` | `(int * tlk_string) list` | language selection; `LOAD_TRA`; `WITH_TRA`; `AUTO_TRA`; `--transin` | immediately → `Dc.trans_strings` stack (`@N` namespace) | never |
| **D** | `Dparser.d_file` | `Dc.action list` | `COMPILE .d` (queued!), `COMPILE_D_TO_DLG`, CLI tools | queued: `Dc.dc` at end of COMPILE | → DLG binary (`Dlg.save_dlg`) |
| **DLG** (binary) | `Dlg.load_dlg` | `Dlg.dlg` | on demand: D action targets an existing dialog; `DLGtoD` decompile | as D-walk input | → binary (`Dlg.save_dlg`); or → D text (`emit_d`) |
| **BAF** | `Bafparser.baf_file` (+ `trigger_list`/`action_list` fragment entries) | `Bcs.script` | `COMPILE .baf`; `EXTEND_*` source; `REPLACE_BCS_BLOCK`; decompile legs | walked only by serializers | → BCS text (`Bcs.save_bcs`); or BAF pretty-print (`Bcs.print_script_text`) |
| **BCS** (text) | `Bcsparser.bcs_file` | `Bcs.script` | `EXTEND_*` destination; `BCStoBAF` decompile | same — serializer-only | → BAF text |
| **IDS** | `idslexer`/`idsparser` via `Bcs.get_ids_map` | symbol map | lazily during BCS/D compile and symbol patch ops | symbol resolution only | `APPEND` rewrites textually |
| **2DA** | **none** — textual ops | — | — | `TP_Patch2DA` ops on the buffer | `PRETTY_PRINT_2DA` via embedded TPP |
| **KEY** | `Key.load_key` | `Key.key` + `resfind` | Phase 1, once | `COPY_EXISTING` lookups | only `MAKE_BIFF`/`DISABLE_FROM_KEY` (immediate) |
| **TLK** | `Tlk.load_tlk` | `tlk_string[]` + `dialog_search` | Phase 1 (active pair, lazy) | `SAY`/`@N`/`STRING_SET` | end of run (`Tlk.save_tlk`) |
| **WeiDU.log** | `Dparser.log_file` | `the_log` | start of queue processing | menu defaults, uninstall ordering | per TP2 file (`save_log`) |

## Nesting / evaluation-order chain

The deepest case — `COMPILE` with `EVALUATE_BUFFER`, `USING`, and a D
action targeting an existing dialog — nests six language families:

```text
TP2 action AST
  → %var% substitution on the .d TEXT (EVALUATE_BUFFER, before any parse)
  → D parser (Dparser)          [PARSE; @N resolved here when inside COMPILE]
  → Dc.action list              [queued, not walked]
  → Dc.dc walk                  [WALK; loads existing .dlg binary → Dlg AST on demand]
  → Dlg AST edits               [COPY_TRANS etc.]
  → Dlg.save_dlg                [SERIALIZE binary]
```

TRA parsing happens *before* the D parse (it feeds `@N`); IDS parsing
happens *during* the D→DLG compile whenever symbol references appear.

## Parse vs Exec: where the walk begins

Every family has a Parse-time AST dump at parse.  Exec-time dumps fire
*immediately before the AST is consumed*:

- TP2 — at the start of `Tpwork.handle_tp` (execution time), even
  though parsing happened earlier in Phase 2;
- TPA/TPP — right before the `process_action` / `process_patch2` fold;
- D — per source file, right before `Dc.dc`;
- BAF — right before `Bcs.save_bcs`;
- WeiDU.log / TRA / IDS — at their respective load/use sites.

The Exec dump is where "this AST is about to have effects" is
observable — exactly the parse/walk boundary the leaf nodes above mark.
See `doc/trace/ast/README.md` for the dump format and the
instrumentation table.
