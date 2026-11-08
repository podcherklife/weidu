# Trace: refactoring-required / deferred filesystem sites

Scope for now: **filesystem reads, writes, deletes, renames, and external
command execution**. The trace records the FS operation or command boundary,
not interpreter state, patch semantics, or variables.

`Case_ins` is out of scope: the trace/rewrite model assumes a case-insensitive
filesystem, so its path-resolution wrappers are not instrumented.

These are the sites where adding a trace event is not a simple call insertion,
or where the current API hides the path/channel/context needed for an accurate
event. They are deliberately **not** part of the first instrumentation slice.

## Caller-channel writes

BCS file output now goes through `Bcs.channel_sink`, which emits `file_write` from
`Bcs.close_sink`. `Bcs.buffer_sink` uses the same close hook but is silent for
now; it can emit buffer-level events later without changing call sites.

| Site | Why it needs work | Proposed handling |
|---|---|---|
| `src/tlk.ml:255` (`Tlk.save_tlk`) | The caller opens the channel. `save_tlk` does know `filename` and the TLK contents, so a filename/entry-count event is possible, but exact channel ownership and close/error accounting are caller-side. | Log at `save_tlk` later, or wrap the channel. TLK writes are deferred beyond the COPY slice. |
| `src/biff.ml:46` (`Biff.save_biff`) / `src/key.ml:114` (`Key.save_key`) | Output channels are opened by callers; component reads and output writes are mixed inside the helpers. | Add semantic events at the callers (`TP_MakeBiff`, `Main` BIFF tools) or pass a trace context. Defer BIFF/KEY creation. |

## Direct writes that bypass the common write helper

| Site | Why it needs work | Proposed handling |
|---|---|---|
| `src/tppatch.ml:1402`, `1476`, `1532` | These branches write `baldur.gam` / `override/baldur.gam` directly with `Case_ins.perv_open_out_bin`; they do not use `Util.open_for_writing`. | Site-level trace calls are possible without refactoring, but a central write funnel would require changing these branches. Defer until the save/`baldur.gam` path is in scope. |
| `src/tpuninstall.ml:270+` (`uninstall_tp2_component`) | Restore is a mixture of `copy_large_file`, direct `perv_open_in_bin` reads, `unix_rename`, and `unix_unlink`; no single semantic write point. | Wrap the restore path with an explicit trace context, or instrument each operation. Defer uninstall tracing. |
| `src/tpaction.ml:1671` (`TP_Compile`) | BAF output now goes through `Bcs.channel_sink`; dialogue output still goes through `Dc`/`emit_dlg_files` without a per-file completion hook. | BCS is covered at the file-owning callers. Add an equivalent completion event at `emit_dlg_files` for DLG. |

## Operation-level gaps that are simple but deferred

These do not require a structural refactor, but they are outside the first
COPY-oriented slice:

- `TP_DecompressBiff` (`src/tpaction.ml:2173`) uses `unix_rename` and `unix_unlink`.
- `TP_Delete` and `TP_Move` are now instrumented at the action level; raw
  `my_unlink`/`my_rmdir` calls outside those actions remain untraced.
- `Tpuninstall` backup-list reads and restores.
- `Tppatch` patch-file reads (`load_file` at `src/tppatch.ml:255`, `267`, `303`, `304`, `325`, `336`, `1283`, `1295`, `1429`).
- Backup-list/bookkeeping writes are covered by the `bookkeeping` `file_write`
  hook in `Util`/`Mymarshal`; the DLC Merger run confirmed all nine previously
  unexplained files.
- CLI-only paths in `src/main.ml`, `src/autoupdate.ml`, `src/mymarshal.ml`,
  `src/kit.ml`, `src/automate.ml`, and `src/sql.ml`.

## Out of scope for the FS boundary

`Tppatch.process_patch2_real` and variable/condition evaluation mutate buffers
or interpreter state; they are not filesystem operations. They should not be
traced under the current boundary.
