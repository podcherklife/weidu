# Execution tracing (`--trace fs`)

WeiDU can record the filesystem operations and external commands of a run
as **JSONL events**, so that they can be compared against a
reimplementation that performs the same operations.  This complements the
AST dumping of `doc/trace/ast` (`--trace ast`): that feature observes the
parse/execute pipeline, this one observes what a run *does* — filesystem
reads, writes, deletes, renames, and external command execution.  No
variables, patch-expression outcomes, or interpreter state are recorded.

## Usage

Both `doc/trace` features share one flag: `--trace` enables **all**
tracing, and an optional qualifier limits it — `fs` for the execution
events documented here, `ast` for the AST dumps of `doc/trace/ast`.  The
events are written as JSONL (one JSON object per line):

- **By default the events go to stdout.**  Each line is flushed as it is
  emitted, so event lines interleave with WeiDU's normal output and with
  the S-expression dumps of `--trace ast` on the same channel; JSON
  objects and S-expressions are trivially distinguishable (leading `{`
  vs leading `(`).
- **`--trace-directory <dir>`** redirects the tracing output to files:
  events go to `<dir>/execution.log` and AST dumps to `<dir>/ast-dumps/`
  (see `doc/trace/ast`).  `<dir>` is created if missing, and a relative
  `<dir>` is resolved against the current working directory.  Passing
  `--trace-directory` without `--trace` is an error.  Only the parts
  enabled by the qualifier are written (e.g. `--trace fs
  --trace-directory traces` creates `execution.log` but no `ast-dumps/`).
- `execution.log` is created per run and truncated on re-init; passing
  `--trace` (or `--trace-directory`) twice just replaces the setting.
- The trace file itself is opened with raw OCaml I/O, not through
  `Util`/`Case_ins`, so it does not recursively trace itself.
- All instrumentation is purely additive: trace failures only produce
  `WARNING:` messages and never alter execution.  If the trace file
  cannot be opened, the run proceeds untraced.

### Common invocations

The flag composes with every existing WeiDU flow:

```sh
# Install with a full trace to stdout:
weidu --noautoupdate --use-lang en_US --force-install 0 --trace setup-mymod.tp2

# Events only, written to a trace directory alongside the AST dumps:
weidu --game <gamedir> --yes --trace fs --trace-directory traces setup-mymod.tp2
#   → traces/execution.log (+ traces/ast-dumps/ if not qualified to fs)
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

1. **`--trace [fs]` / `--trace-directory <dir>`** — `src/main.ml`;
   configures the sink (stdout or `<dir>/execution.log`), initializes the
   trace before game loading, and writes `run_start`.
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

## What is not traced

This section is a complete accounting of the filesystem accesses that
produce no event, or only a partial one, grouped by mechanism.  It was
compiled by sweeping `src/` for every channel-creation and mutation
primitive (`perv_open_*`, `open_in`/`open_out*`, `unix_openfile`,
`unix_rename`/`unix_unlink`/`unix_mkdir`, `sys_remove`/`sys_readdir`,
`my_unlink`/`my_rmdir`, `recursive_mkdir`, `copy_large_file`,
`open_for_writing`, `exec_command`/`Unix.system`/`Sys.command`,
`Marshal.to_channel`, and C stubs); if you change how WeiDU touches the
filesystem, re-run that sweep and update this list.

Writes have three coverage tiers:

1. **Full events** (open *and* completion with byte counts) — the
   `file_write`/`file_copy`/`file_move`/`file_delete` emitters listed
   under *What is instrumented*.
2. **Open-only** — `Util.open_for_writing` fires `file_write_open`, but
   the writer closes its channel directly, so no completion event with
   the final byte count is emitted.
3. **Invisible** — the access uses raw I/O and produces no event at all.

### Open-only writes (tier 2)

These all go through `Util.open_for_writing` (so the destination and
backup flag are visible in a `file_write_open` event) but complete
without a traced event:

- **TLK saves** — the `save_tlk` wrapper in `src/main.ml` (end-of-install
  `dialog.tlk`/`dialogf.tlk` saves, `--tlkout`, `--tlkmerge`); the
  channel is handed to `Tlk.save_tlk`, which does not close it through a
  sink.
- **KEY saves** — the key-rewriting TP2 actions (`TP_DisableFromKey`,
  `TP_MakeBiff`) in `src/tpaction.ml` open the key file with
  `open_for_writing` and hand the channel to `Key.save_key`.
- **BIFF saves** — `Biff.save_biff` (`src/biff.ml`) opens its own
  `open_for_writing` channel and writes through a raw fd.
- **DLG saves** — `Parsewrappers.emit_dlg_files` (all compiled dialogue
  output, including `TP_Compile`) buffers the DLG, then
  `open_for_writing` + `close_out` with no completion hook.
- **Text patch actions** — the file-appending actions (`APPEND`,
  `APPEND_COLUMN`, `SET_COLUMN`) in `src/tpaction.ml` write their
  destination with `open_for_writing` + `close_out` (inlined variants
  write nothing and are invisible by design).
- **`--sql`** — `override/bgee.sql` (`src/sql.ml`).
- **Self-update** — `src/autoupdate.ml` writes the updated WeiDU copies
  (this runs during normal installs, not only CLI flows; disabled by
  `--noautoupdate`).
- **CLI tool outputs in `src/main.ml`** — the resource-extraction flows
  (`--unbiff`, `--biff-get`), the BIFF/KEY maintenance flows
  (`--make-biff`, `--remove-biff`, including the `CHITIN.KEY` rewrite),
  and the `.D`/TRA translation outputs written through `--out`
  (`--trans`, `--traify`, `--traify-tlk`, `--forceify`).

### Invisible writes (tier 3)

- **`--log <file>` / `--logapp`** — the debug log channel
  (`Util.init_log`) is opened with `Case_ins.perv_open_out(_gen)` and
  closed at exit; it runs during installs, not only CLI flows.
- **Error dumps** — `Util.get_error_chn`/`Util.error` write
  `errors/<sort>` files on parse errors.
- **SPELL.IDS bookkeeping** — `override/spell.ids.installed`
  (`Util`, on the first backup of `OVERRIDE/SPELL.IDS`),
  `override/spell.ids.<mod>.<n>.marker` (`Tpuninstall.check_pre_hooks`),
  and the conditional exit-time `my_unlink` of
  `override/add_spell.ids` (`src/main.ml`).
- **C-level cache decompression** — `Cbif.cbf2bif` is a C stub; the
  `cache/<bif>` file it writes (and the `cache/` directory it creates)
  are invisible to OCaml-level instrumentation by construction.
- **`copy_large_file` pre-copy unlink** — when the destination already
  exists it is removed (`my_unlink`) before the raw-fd copy; that
  removal emits no event (the subsequent copy does).
- **Exit-time temporary-file cleanup** — `Load.cbifs_to_rem` (cached
  decompressed BIFF copies under `cache/`) are removed with `my_unlink`
  at the end of the run.
- **Self-update cleanup** — `src/autoupdate.ml` unlinks outdated WeiDU
  copies before rewriting them.
- **`baldur.gam` direct writes** — the three `Case_ins.perv_open_out_bin`
  branches in `src/tppatch.ml` (`baldur.gam`, `override/baldur.gam`).
- **`TP_DecompressBiff`** — writes the decompressed BIFF with
  `Case_ins.perv_open_out_bin` and uses raw `unix_rename`/`unix_unlink`.
- **`--tolower`** — `src/tolower.ml` uses raw `open_out`/`open_in`
  (`linux.ini` and the ini files it reads), bypassing even `Case_ins`.
- **`--extract-kits`** — `src/kit.ml` writes kit files with
  `Case_ins.perv_open_out_bin`.
- **AST dump files** — `--trace ast` output (`Astdump.write_dump`) is
  instrumentation output like the trace file itself and is not traced.

### Reads not traced

- **BIFF container reads.** `Biff.load_biff`/`extract_file`/`extract_tis`
  read BIFFs through raw file descriptors.  Their content is represented
  semantically by `resource_read` (provenance, BIFF path, offset,
  container size, compression) — no `file_read` event is emitted for the
  container itself.  `chitin.key`, by contrast, is read through
  `Util.load_file` and is traced.
- **Backup bookkeeping reads.** The `Mymarshal` readers
  (`read_unsetstr`, `read_tlkpath`, `read_cli_vars`, `read_readln`) and
  the direct `Case_ins.perv_open_in_bin` reads of the
  `UNINSTALL`/`MAPPINGS`/`MOVE` lists in `src/tpuninstall.ml` are not
  traced (their writes are).
- **CLI direct parser reads.** A few `src/main.ml` flows read files with
  raw `Case_ins.perv_open_in` instead of `Util.parse_file`: the
  `--forceify` `.D` read, the `--tlkcmp` sources, and the old-TRA input
  of `--traify`.

### Uninstall/restore (partially traced)

`Tpuninstall` restores are traced only where they go through
`copy_large_file` (visible as `file_copy` with reason
"restoring a backup").  Not traced: the backup-list reads above, MOVE
restores (`Case_ins.unix_rename`), deletions (`my_unlink` of
restored-then-removed files, `READLN`/`ARGS`/`UNSETSTR`/`TLKPATH` backup
cleanup including `.TEXT` companions, marker unlink), the empty-backup
directory `my_rmdir` cleanup, the `recursive_mkdir` of restore
directories, and the SPELL.IDS marker writes.

### External command exceptions

`Util.exec_command` traces `AT_NOW`, `AT_EXIT`, `AT_UNINSTALL` and their
interactive variants (start/end event pairs).  Untraced executions:

- the **readme `VIEW` prompt** (`Tpwork.do_readme`) runs the viewer with
  a direct `Unix.system` after user confirmation;
- the **interactive "Enter arguments" re-exec** (`src/main.ml`) uses
  `Sys.command` to re-run WeiDU itself — the child process re-traces if
  `--trace` is part of its arguments;
- the separate **`weinstall`** binary runs WeiDU via `Unix.system`.

### Operation classes with no events

- **Directory creation** (`recursive_mkdir` for backup/restore
  directories, `Load`'s `override` mkdir, `cache/`), **directory
  deletion** outside `TP_Delete` (empty-backup-dir cleanup), and
  **directory listing** (`sys_readdir`).
- **Probes** — `file_exists`, `unix_stat64`, `unix_access`:
  existence/size/permission checks are not recorded.
- **Attribute changes** — `unix_chmod` after file writes, self-update
  chmod.
- **Filesystem effects inside external commands** — only the command
  invocation and its completion are traced; whatever the child process
  does is outside the trace.

### Out of scope for the FS boundary

`Tppatch.process_patch2_real` and variable/condition evaluation mutate
buffers or interpreter state; they are not filesystem operations.

## Comparing a trace against a filesystem diff

The intended workflow: run the same install once traced and once
untraced, verify the outputs are identical, then check trace coherence
against the final tree:

- Exclude the trace output itself (`execution.log`, and any
  `ast-dumps/` directory) and any backup files outside the fixture's
  expected output from the comparison.
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
