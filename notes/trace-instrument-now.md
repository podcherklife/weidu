# Trace: filesystem and external-command hooks

Scope: **filesystem reads, writes, deletes, renames, and external command
execution**. No variables, patch-expression outcomes, or interpreter state in
this slice.

## Assumption: case-insensitive filesystem

This trace and the compatibility rewrite assume the host filesystem is
case-insensitive. `Case_ins` path resolution is therefore out of scope and is
not instrumented. Trace paths are treated as case-insensitive for comparison;
case-only aliases such as `WeiDU.log` and `weidu.log` refer to the same file.

Tests should use WeiDU's default Linux case folding (`case_fold = true`). Do not
use `--no-case-fold` or `--lowercase` for runs intended to match this model.

The trace is opt-in via `--trace <path>` and is written as JSONL, one JSON
object per line. A relative `<path>` is resolved against the directory
containing the TP2 being installed, so `--trace aug-smoke.jsonl` lands in the
mod directory. Absolute paths are used as-is. The trace file itself is opened
with raw OCaml I/O, not through `Util`/`Case_ins`, so it does not recursively
trace itself.

## Event stream

Common fields:

- `ts` — wall-clock timestamp
- `seq` — monotonically increasing event number
- `event` — event type

Initial events:

| Event | Emitted from | Meaning |
|---|---|---|
| `run_start` | `src/main.ml` after argument parsing | Trace schema, WeiDU version, cwd, argv, pid, trace path |
| `resource_read` | `src/load.ml:633` (`Load.load_resource`) | Semantic resource read with provenance |
| `file_read` | `src/util.ml:514` (`Util.load_file`) | Direct file read |
| `file_read` | `src/util.ml` (`Util.parse_file`) | Direct read owned by the generic parser (TP2/BAF/DLG/TRA/log) |
| `file_read` | `src/util.ml` (`Util.read_lines`) | Line-oriented direct read (`weidu.conf`, GemRB paths, changelog) |
| `file_write_open` | `src/util.ml:565` (`Util.open_for_writing_internal`) | A file was opened for writing |
| `file_copy` | `src/util.ml:468` (`Util.copy_large_file`) | Raw-fd copy/backup completed |
| `file_delete` | `src/tpaction.ml` (`TP_Delete`) | File or directory deleted; records path, kind, byte count, and backup flag |
| `file_move` | `src/tpaction.ml` (`TP_Move`) | Rename completed; records source, destination, byte count, and backup flag |
| `external_exec_start` | `src/util.ml` (`Util.exec_command`) | External shell command is about to run; records command, exact flag, and cwd |
| `external_exec_end` | `src/util.ml` (`Util.exec_command`) | External command completed; records command, status, and status code (launch/read errors use `status: "error"` plus `error`) |
| `file_write` | `src/tpaction.ml:853` (`TP_Copy`) | COPY output completed |
| `file_write` | `src/tpstate.ml:377` (`Tpstate.save_log`) | `WeiDU.log` write completed |
| `file_write` | `src/util.ml` (`Util.save_conf`) | `weidu.conf` write completed (`kind: config`) |
| `file_write` | `src/util.ml` (`Util.trace_bookkeeping_file`) and `src/mymarshal.ml` | Backup bookkeeping file completed (`kind: bookkeeping`); `detail` names the role (`UNINSTALL`, `MAPPINGS`, `MOVE`, `OTHER`, `ARGS`, `READLN`, `TLKPATH`, `UNSETSTR`, or a `.TEXT` companion) |
| `file_write` | `src/bcs.ml` (`Bcs.channel_sink` close) | BCS/BAF output completed (`kind: bcs` or `baf`) |
| `trace_end` | `Trace.close` | Trace channel is closing |

`file_write_open` does not know the final byte count; it records `bytes: null`.
The action-level `file_write`/`file_copy` events record the completed size.

When comparing the trace against a filesystem diff, exclude the trace file
itself and any backup list/log files that are not part of the fixture's
expected output.

## Provenance

`resource_read.source` is one of:

- `override` — found in an override/search path
- `bif` — extracted from a BIFF through `chitin.key`
- `direct` — read directly from the given path
- `missing` — resource was allowed to be missing
- `unknown` — the path cannot be classified

When `source` is `bif`, the event also carries `bif`, `bif_index`, `tis_index`,
`offset`, `container_size`, and `compressed` from the BIFF metadata.

`resource_read` suppresses the generic `file_read` for the same `load_file`
calls inside `Load.load_resource`; resource loads therefore appear once, as a
semantic event. Other direct reads still appear as `file_read`.

## Hooks in this slice

1. **`Trace` module** — standalone JSONL writer, raw `open_out_bin`, no project
   dependencies. Added before `case_ins` in `Depends`; no `Case_ins` hooks are
   planned under the case-insensitive filesystem assumption.
2. **`--trace <path>`** — `src/main.ml`; initializes the trace before game
   loading and writes `run_start`.
3. **`Util.load_file`** — `file_read` with path, byte count, source, and detail.
4. **`Load.load_resource`** — `resource_read` with resource name/extension,
   caller (`for_what`), source kind, path, byte count, and BIFF provenance.
5. **`Util.open_for_writing_internal`** — `file_write_open` with path, binary
   flag, and backup flag.
6. **`Util.copy_large_file`** — `file_copy` with src, dst, bytes, and reason.
7. **`TP_Copy` write branch** — `file_write` with destination, source, byte
   count, backup flag, and kind `copy`. Inlined COPYs do not write a file and
   do not emit a write event.
8. **`Tpstate.save_log`** — `file_write` for `WeiDU.log`, kind `weidu_log`.
9. **`Util.parse_file` file branch** — `file_read` for files opened directly
   by the generic parser, including the TP2, BAF, DLG, TRA, and log readers.
   Byte count comes from `in_channel_length` at open time.
10. **`Util.read_lines`** — `file_read` for line-oriented direct reads such as
    `weidu.conf`, GemRB data paths, and changelog backups.
11. **`Util.save_conf`** — `file_write` for `weidu.conf`, kind `config`; the
    byte count is accumulated from the emitted lines.
12. **`Bcs.channel_sink` / `Bcs.buffer_sink`** — reusable BCS output sinks.
    `channel_sink` captures the destination path and emits `file_write` from
    `Bcs.close_sink`; `buffer_sink` is intentionally silent for now but has the
    same close hook for a future buffer event.
13. **`Util.exec_command`** — emits `external_exec_start` before and
    `external_exec_end` after every external command run by TP2 actions,
    including `AT_NOW`, `AT_EXIT`, `AT_UNINSTALL`, and their interactive
    variants. The event records the final shell command, the `exact` flag, the
    working directory, and the process status/status code.
14. **`TP_Delete`** — emits `file_delete` after each successful file removal
    and directory removal. File events carry `kind: "file"`, the byte count
    from `stat64`, and the action's backup flag; directory events carry
    `kind: "directory"` and `bytes: null`.
15. **`TP_Move`** — emits `file_move` after each successful rename, with the
    resolved source and destination, the source byte count, and the action's
    backup flag. The existing destination-exists fallback still goes through
    `TP_CopyLarge`, so it appears as `file_copy` rather than `file_move`.
16. **Backup bookkeeping** — the `UNINSTALL`, `MAPPINGS`, `MOVE`, and `OTHER`
    channels are closed through `Util.close_bookkeeping_channel`, which emits
    `file_write` with `kind: bookkeeping` and the final file size. The
    `Mymarshal` writers for `ARGS`, `READLN`, `TLKPATH`, and `UNSETSTR` emit the
    same event for both the binary/file and `.TEXT` outputs.

## Known gaps

The first traced install confirmed the hooks above. The follow-up DLC Merger
runs closed the `TP_Delete`/`TP_Move` and backup-bookkeeping gaps. These
coverage gaps remain:

- Some direct parser/line readers still bypass `Util.parse_file` or
  `Util.read_lines` (for example restore paths).
- The case-insensitive filesystem reports the log as either `WeiDU.log` or
  `weidu.log`; normalize those aliases when comparing a trace to a filesystem
  diff.

The trace file itself is excluded from comparisons. Backup bookkeeping now
emits `file_write` events, so it can be included in expected-write sets.

### DLC Merger coherence check (2026-10-31, delete/move and bookkeeping)

A fresh component-1 install from the pristine tree, using the rebuilt binary
with the `TP_Delete`/`TP_Move` and bookkeeping hooks, produced a raw
case-sensitive diff of 1,099 added, 603 changed, and 10 removed paths. Under
the case-insensitive comparison used by the trace model, that is 1,090 added,
612 changed, and 1 removed.

- All 612 normalized changes have trace write events: 603 ordinary changes
  plus the nine `dialogF.tlk` -> `dialogf.tlk` case-spelling replacements.
- All 1,090 normalized additions have trace write events. The nine backup
  bookkeeping files under `weidu_external/backup/DlcMerger/1/` now emit
  `file_write` events: `ARGS.1`, `ARGS.1.TEXT`, `MAPPINGS.1`, `MOVE.1`,
  `OTHER.1`, `READLN.1`, `READLN.1.TEXT`, `TLKPATH.1`, and `UNINSTALL.1`.
- The one removed path is `sod-dlc.zip`, and the move target
  `sod-dlc.disabled` is covered by a single `file_move` event:
  `./sod-dlc.zip` -> `./sod-dlc.disabled`, 1,931,414,699 bytes. The trace and
  final file size agree.
- The run emitted 1,165 `file_delete` events: 1,078 files and 87 directories.
  Every delete path is under `weidu_external/temp/`, and every delete path is
  absent from the final tree.
- No trace write destination is missing from the final tree, and the last
  byte-bearing event for every one of the 1,702 write destinations matches the
  final file size. The only traced read path without a final file is the
  temporary `weidu_external/temp/DlcMerger/mod.key`; the run also emits a
  matching `file_delete` for that path after use.

The mod runs three external `unzip` commands through `AT_NOW`. The trace
contains matching `external_exec_start`/`external_exec_end` pairs for all
three, each with `status: "exited"` and `status_code: 0`. Filesystem operations
performed inside those child processes remain outside the trace; only the
subsequent WeiDU `file_copy` destinations are captured as individual writes.

## Deliberately not in this slice

- Low-level `Case_ins` wrappers; excluded by the case-insensitive filesystem
  assumption.
- `Biff.extract_file`/`extract_tis` as separate events; their provenance is
  already carried by `resource_read`.
- TLK/BIFF/KEY save paths; caller-channel work is required.
- Filesystem operations performed inside external commands; only the command
  invocation and its completion are traced.
- `TP_DecompressBiff`, `Tpuninstall`.
- `Tppatch` patch-file reads and direct `baldur.gam` writes.
- CLI-only and auxiliary output paths.
- Variables, conditions, and patch operations; they are not FS operations.

## Smoke fixture

`test/trace-smoke/` is the first fixture. It performs one local `COPY` and one
`COPY_EXISTING ~ANIMATE.IDS~`; see its README for the game-root command and
expected writes.
