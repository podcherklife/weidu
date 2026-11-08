# Execution tracing (`--trace`)

WeiDU can record the filesystem operations and external commands of a run
as **JSONL events**, so that they can be compared against a
reimplementation that performs the same operations.  This complements the
AST dumping of `doc/trace/ast` (`--dump-ast`): that feature observes the
parse/execute pipeline, this one observes what a run *does* — filesystem
reads, writes, deletes, renames, and external command execution.  No
variables, patch-expression outcomes, or interpreter state are recorded.

## Usage

Add `--trace <path>` to any normal WeiDU command line.  When the flag is
given, events are written as JSONL (one JSON object per line) to a single
file:

- A relative `<path>` is resolved against the directory containing the
  TP2 being installed, so `--trace aug.jsonl` lands in the mod
  directory.  Absolute paths are used as-is.  A missing single-level
  parent directory is created (mirroring `--dump-ast`).
- The trace file is created per run and truncated on re-init; passing
  `--trace` twice just replaces the setting.
- The trace file itself is opened with raw OCaml I/O, not through
  `Util`/`Case_ins`, so it does not recursively trace itself.
- All instrumentation is purely additive: trace failures only produce
  `WARNING:` messages and never alter execution.  If the trace file
  cannot be opened, the run proceeds untraced.

### Common invocations

The flag composes with every existing WeiDU flow, and with `--dump-ast`;
both flags can be given to observe the parse pipeline and the filesystem
effects of the same run.

```sh
# Install with a trace (relative path lands in the mod directory):
weidu --noautoupdate --use-lang en_US --force-install 0 --trace aug.jsonl setup-mymod.tp2

# Trace to an absolute location, alongside AST dumps:
weidu --game <gamedir> --yes --dump-ast dumps --trace /tmp/aug.jsonl setup-mymod.tp2
```

### Assumption: case-insensitive filesystem

The trace (and the compatibility rewrite it supports) assumes the host
filesystem is case-insensitive.  `Case_ins` path resolution is therefore
out of scope and is not instrumented; trace paths are compared
case-insensitively, and case-only aliases such as `WeiDU.log` and
`weidu.log` refer to the same file.  Tests should use WeiDU's default
Linux case folding (`case_fold = true`); do not use `--no-case-fold` or
`--lowercase` for runs intended to match this model.

## Event stream

Common fields on every event: `ts` (wall-clock Unix time), `seq`
(monotonically increasing per run), `event` (type).  Every run starts
with a `run_start` event (schema `weidu-fs-trace-v1`, WeiDU version, cwd,
argv, pid, trace path) and ends with `trace_end` when the trace channel
closes.

| Event | Emitted from | Meaning |
|---|---|---|
| `run_start` | `src/main.ml` after argument parsing | Trace schema, WeiDU version, cwd, argv, pid, trace path |
| `resource_read` | `src/load.ml` (`Load.load_resource`) | Semantic resource read with provenance |
| `file_read` | `src/util.ml` (`Util.load_file`) | Direct file read |
| `file_read` | `src/util.ml` (`Util.parse_file`) | Direct read owned by the generic parser (TP2/BAF/DLG/TRA/log) |
| `file_read` | `src/util.ml` (`Util.read_lines`) | Line-oriented direct read (`weidu.conf`, GemRB paths, changelog) |
| `file_write_open` | `src/util.ml` (`Util.open_for_writing_internal`) | A file was opened for writing |
| `file_copy` | `src/util.ml` (`Util.copy_large_file`) | Raw-fd copy/backup completed |
| `file_delete` | `src/tpaction.ml` (`TP_Delete`) | File or directory deleted; records path, kind, byte count, and backup flag |
| `file_move` | `src/tpaction.ml` (`TP_Move`) | Rename completed; records source, destination, byte count, and backup flag |
| `external_exec_start` | `src/util.ml` (`Util.exec_command`) | External shell command is about to run; records command, exact flag, and cwd |
| `external_exec_end` | `src/util.ml` (`Util.exec_command`) | External command completed; records command, status, and status code (launch/read errors use `status: "error"` plus `error`) |
| `file_write` | `src/tpaction.ml` (`TP_Copy`) | COPY output completed |
| `file_write` | `src/tpstate.ml` (`Tpstate.save_log`) | `WeiDU.log` write completed (`kind: weidu_log`) |
| `file_write` | `src/util.ml` (`Util.save_conf`) | `weidu.conf` write completed (`kind: config`) |
| `file_write` | `src/util.ml` (`Util.trace_bookkeeping_file`) and `src/mymarshal.ml` | Backup bookkeeping file completed (`kind: bookkeeping`); `detail` names the role (`UNINSTALL`, `MAPPINGS`, `MOVE`, `OTHER`, `ARGS`, `READLN`, `TLKPATH`, `UNSETSTR`, or a `.TEXT` companion) |
| `file_write` | `src/bcs.ml` (`Bcs.channel_sink` close) | BCS/BAF output completed (`kind: bcs` or `baf`) |
| `trace_end` | `Trace.close` | Trace channel is closing |

Notes:

- `file_write_open` does not know the final byte count and records
  `bytes: null`; the action-level `file_write`/`file_copy` events record
  the completed size.
- Read events are emitted on success only: a read whose parse fails
  leaves no event, because no value was produced.  Failed external
  launches do emit `external_exec_end` with `status: "error"`.
- `resource_read` suppresses the generic `file_read` for the same
  `load_file` calls inside `Load.load_resource`; resource loads appear
  once, as a semantic event.  Other direct reads still appear as
  `file_read`.

## Provenance

`resource_read.source` is one of:

- `override` — found in an override/search path
- `bif` — extracted from a BIFF through `chitin.key`
- `direct` — read directly from the given path
- `missing` — resource was allowed to be missing
- `unknown` — the path cannot be classified

When `source` is `bif`, the event also carries `bif`, `bif_index`,
`tis_index`, `offset`, `container_size`, and `compressed` from the BIFF
metadata.

## What is instrumented

Instrumentation call sites are listed here; the pieces live in:

- `src/trace.ml` — writer core: JSON encoding, event emitters, sequence
  numbering, and the run/`trace_end` lifecycle.  Standalone (no project
  dependencies), so it can be used from `Case_ins` as well as
  `Util`/`Load`.
- `Depends` — `trace` sits before `case_ins`/`util` so every layer can
  emit.

1. **`--trace <path>`** — `src/main.ml`; resolves the path, initializes
   the trace before game loading, and writes `run_start`.
2. **`Util.load_file`** — `file_read` with path, byte count, source, and
   detail.
3. **`Load.load_resource`** — `resource_read` with resource name and
   extension, caller (`for_what`), source kind, path, byte count, and
   BIFF provenance.  The inner `load_file` calls are wrapped in
   `Trace.without_file_read` so only the semantic event appears.
4. **`Util.open_for_writing_internal`** — `file_write_open` with path,
   binary flag, and backup flag.
5. **`Util.copy_large_file`** — `file_copy` with src, dst, bytes, and
   reason.
6. **`TP_Copy` write branch** — `file_write` with destination, source,
   byte count, backup flag, and kind `copy`.  Inlined COPYs do not write
   a file and do not emit a write event.
7. **`Tpstate.save_log`** — `file_write` for `WeiDU.log`, kind
   `weidu_log`.
8. **`Util.parse_file` file branch** — `file_read` for files opened
   directly by the generic parser, including the TP2, BAF, DLG, TRA, and
   log readers.  Byte count comes from `in_channel_length` at open time.
9. **`Util.read_lines`** — `file_read` for line-oriented direct reads
   such as `weidu.conf`, GemRB data paths, and changelog backups.
10. **`Util.save_conf`** — `file_write` for `weidu.conf`, kind `config`;
    the byte count is accumulated from the emitted lines.
11. **`Bcs.channel_sink` / `Bcs.buffer_sink`** — reusable BCS output
    sinks.  `channel_sink` captures the destination path and emits
    `file_write` from `Bcs.close_sink`; `buffer_sink` is silent for now
    but has the same close hook for a future buffer event.
12. **`Util.exec_command`** — emits `external_exec_start` before and
    `external_exec_end` after every external command run by TP2 actions,
    including `AT_NOW`, `AT_EXIT`, `AT_UNINSTALL`, and their interactive
    variants.  The events record the final shell command, the `exact`
    flag, the working directory, and the process status/status code.
13. **`TP_Delete`** — emits `file_delete` after each successful file
    removal and directory removal.  File events carry `kind: "file"`, the
    byte count from `stat64`, and the action's backup flag; directory
    events carry `kind: "directory"` and `bytes: null`.
14. **`TP_Move`** — emits `file_move` after each successful rename, with
    the resolved source and destination, the source byte count, and the
    action's backup flag.  The existing destination-exists fallback goes
    through `TP_CopyLarge`, so it appears as `file_copy` rather than
    `file_move`.
15. **Backup bookkeeping** — the `UNINSTALL`, `MAPPINGS`, `MOVE`, and
    `OTHER` channels are closed through `Util.close_bookkeeping_channel`,
    which emits `file_write` with `kind: bookkeeping` and the final file
    size.  The `Mymarshal` writers for `ARGS`, `READLN`, `TLKPATH`, and
    `UNSETSTR` emit the same event for both the binary/file and `.TEXT`
    outputs.

## Deliberate exclusions and known limitations

These sites are *not* traced, with reasons:

1. **Low-level `Case_ins` wrappers.** Excluded by the case-insensitive
   filesystem assumption above.
2. **Caller-channel writes** — the caller opens the channel, so the
   helper cannot emit a complete, accurately-sized event without
   refactoring:
   - `src/tlk.ml` (`Tlk.save_tlk`) — a filename/entry-count event is
     possible, but channel ownership and close/error accounting are
     caller-side.
   - `src/biff.ml` (`Biff.save_biff`) / `src/key.ml` (`Key.save_key`) —
     output channels are opened by callers; semantic events belong at the
     callers (`TP_MakeBiff`, `Main` BIFF tools).
3. **Direct writes that bypass the common write helper:**
   - `src/tppatch.ml` (`baldur.gam` branches) — write directly with
     `Case_ins.perv_open_out_bin`; a central write funnel would require
     restructuring those branches.
   - `src/tpuninstall.ml` (`uninstall_tp2_component`) — restore mixes
     `copy_large_file` (traced), direct reads, `unix_rename`, and
     `unix_unlink`; the uninstall path is only partially traced
     (restores appear as `file_copy`, deletions do not appear).
   - `src/tpaction.ml` (`TP_Compile`) — BAF output is covered through
     `Bcs.channel_sink`; dialogue output still goes through
     `Dc`/`emit_dlg_files` without a per-file completion hook.
4. **Operation-level gaps that are simple but deferred:**
   - `TP_DecompressBiff` uses raw `unix_rename`/`unix_unlink`.
   - Raw `my_unlink`/`my_rmdir` calls outside `TP_Delete`/`TP_Move`.
   - `Tpuninstall` backup-list reads and cleanup.
   - `Tppatch` patch-file reads (`load_file` at the patch processing
     sites).
   - CLI-only paths in `src/main.ml`, `src/autoupdate.ml`,
     `src/kit.ml`, `src/automate.ml`, and `src/sql.ml`.
5. **Out of scope for the FS boundary.** `Tppatch.process_patch2_real`
   and variable/condition evaluation mutate buffers or interpreter
   state; they are not filesystem operations.
6. **Filesystem operations performed inside external commands.** Only
   the command invocation and its completion are traced; whatever the
   child process does to the filesystem is outside the trace.

## Comparing a trace against a filesystem diff

The intended workflow: run the same install once traced and once
untraced, verify the outputs are identical, then check trace coherence
against the final tree:

- Exclude the trace file itself (and any backup files outside the
  fixture's expected output) from the comparison.
- Normalize path case (`WeiDU.log` vs `weidu.log`) under the
  case-insensitive assumption.
- Every write destination must exist in the final tree with the byte
  count recorded by its last `file_write`/`file_copy` event.
- Every deletion must be absent from the final tree.

A full DLC Merger component install was validated this way (raw diff of
1,099 added / 603 changed / 10 removed paths; 1,090 / 612 / 1 under
case-insensitive normalization): all normalized additions and changes
had trace write events, the single removed path and its move target were
covered by one `file_move` (1,931,414,699 bytes, matching the final file
size), all 1,165 `file_delete` paths were under `weidu_external/temp/`
and absent from the final tree, and the three external `unzip` commands
(`AT_NOW`) produced matching `external_exec_start`/`external_exec_end`
pairs with `status: "exited"`, `status_code: 0`.

`test/trace-smoke/` is the small fixture: one local `COPY` and one
`COPY_EXISTING ~ANIMATE.IDS~`; see its README for the game-root command
and expected writes.
