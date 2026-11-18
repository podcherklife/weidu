# Backup drilldown: how WeiDU backs up and restores files

This document is a drilldown of WeiDU's file-backup machinery: where the
backups live on disk, the exact moment (and conditions) at which the
backup copy of a file is made, and how those copies are consumed again
when a component is uninstalled — or when a failed install is rolled
back.  It complements `doc/trace/architecture-drilldown.md`, which
places the backup bookkeeping in its install-phase narrative (Phase 4
step 2 and Phase 7), and `doc/trace/execution/README.md`, whose
`--trace fs` events observe these operations from the outside.

Like the other drilldowns it is written so that the behavior it
describes can be compared against a reimplementation: each claim names
the module that implements it.

## Notation

- **backup root** — the directory named by the TP2 `BACKUP` header.
  It is resolved relative to the *working directory*: WeiDU never
  chdirs, so the game root must be the cwd when it runs (as with every
  other game-relative path it writes).
- **component dir** — `<backup root>/<component index>`, e.g.
  `mymod/backup/0/` for component `0`.
- **bookkeeping file** — one of the per-component journals inside the
  component dir, described below.  "Journal" emphasizes the write
  discipline: every entry is flushed to disk as it is appended, so the
  file is a valid record of the operations performed so far even after
  a crash.
- Paths are recorded as the writing action normalized them; the
  `COPY` family stores slash-separated paths, `DELETE` stores the
  native-separator form of the name it was given.

WeiDU's uninstall does **not** treat the backup dir as a directory
tree of saved files to walk.  The saved copies are named artifacts
addressed through journals, and the *journals* — not the copies — are
what the uninstall machinery reads.

## Where backups live

The location is chosen entirely by the mod.  `BACKUP ~X~` is the
mandatory first header keyword of every TP2 (`src/toldparser.mly`,
`src/trealparserin.in`); its value is stored in `Tp.backup` verbatim,
with only `\` normalized to `/`.  No suffix is ever appended: a mod
saying `BACKUP ~MyMod/backup~` gets component dirs
`MyMod/backup/0/`, `MyMod/backup/1/`, ...  (The `test/trace-smoke`
fixture uses `BACKUP ~trace-smoke/backup~`.)  The directory is created
on demand; it is never removed if non-empty.

`Util.set_backup_dir` (`src/util.ml`), called from `Tpwork.handle_tp`
(`src/tpwork.ml`) once a component passes its `REQUIRE_*` checks —
before the builtin TPA include, `ALWAYS` actions, and the component
body — does four things:

1. creates the component dir recursively;
2. closes the previous component's bookkeeping channels;
3. clears `Util.backup_ht`, the "already backed up in this component"
   table;
4. opens the four write-ahead journals of the new component dir:
   `UNINSTALL.<n>`, `MAPPINGS.<n>`, `MOVE.<n>` and `OTHER.<n>`.

The remaining bookkeeping files are written on demand around the
component body:

| File | Records | Written by | Consumed by |
|---|---|---|---|
| `UNINSTALL.<n>` | one game path per line: every path the component wrote, created or deleted | `Util.backup_if_extant`, `src/util.ml` | `Tpuninstall.uninstall_copy` |
| `MAPPINGS.<n>` | `path<TB#"SPACE">backup-copy-path` pairs | `Util.backup_if_extant` | `Tpuninstall.uninstall_copy` |
| `MOVE.<n>` | `src<TB#"SPACE">dst` pairs | `TP_Move`, `src/tpaction.ml` | `Tpuninstall.uninstall_move` |
| `OTHER.<n>` | informational records: paths handled *without* backup (`+` prefix), `DELETE` targets (even backed-up ones), MOVE endpoints, `MAKE_BIFF` contents, `DISABLE_FROM_KEY` entries | `Util.record_other_file_op` and friends | nobody — deleted unread at uninstall |
| `UNSETSTR.<n>` (+`.TEXT`) | `(strref, male text, female text)` triples capturing the pre-edit text of each `STRING_SET`/`SET_STRING` | `Tpuninstall.record_strset_uninstall_info` at component end (and rollback) | `Tpuninstall.uninstall_strset` |
| `TLKPATH.<n>` | the `dialog.tlk`/`dialogf.tlk` paths active during install | `Tpuninstall.record_tlk_path_info` | `Tpuninstall.uninstall_strset` |
| `ARGS.<n>` (+`.TEXT`) | the `%argv[N]%` values in effect | `Tpwork.handle_cli_vars` at component start | later non-interactive install of the same component |
| `READLN.<n>` (+`.TEXT`) | the `READLN` answers given interactively | `Mymarshal.write_readln` at end of an interactive install | later non-interactive install (`Mymarshal.read_readln`) |

`UNSETSTR.<n>` and the `.TEXT` variants use a binary marshal format
with a text fallback (`src/mymarshal.ml`); the journals are plain
text.  `ARGS.<n>`/`READLN.<n>` make the backup dir double as storage
for reinstall answers: a component temporarily uninstalled by a stack
uninstall is reinstalled non-interactively at the end of the run and
answers from these files instead of prompting again.

### One backup per path per component

`Util.backup_ht` guarantees that within one component a given path is
backed up at most once.  The copy therefore holds the state of the
file *before the component ran*, not a per-write history: the first
write decides what is preserved, and every later write by the same
component lands on top of the mod's own first result.  A second
component overwriting the same file makes its own, newer backup copy
in its own component dir — that chain of copies is what makes stack
uninstalls work (see below).

## The moment a backup copy is made

There is exactly one choke point.  Every game-file write goes through
`Util.open_for_writing`, i.e. `open_for_writing_internal` with backup
enabled (`src/util.ml`), and every game-file deletion through
`Util.backup_if_extant` plus the action's own unlink.  The decision
sequence inside `Util.backup_if_extant` is:

1. **Already backed up?**  If the (uppercased, native-separator) path
   is in `Util.backup_ht`, do nothing — see "one backup per path per
   component" above.
2. **`OVERRIDE/SPELL.IDS` special case.**  Before spelling `spell.ids`
   into the journal, WeiDU ensures the marker file
   `override/spell.ids.installed` exists (backing it up first if it is
   extant, otherwise creating it containing `spell.ids edits
   installed`).  This marker, together with the per-component
   `override/spell.ids.<mod>.<n>.marker` files written during
   uninstall, tells the end-of-run cleanup (`src/main.ml`) whether
   WeiDU-created `spell.ids` edits are live and whether the
   `ADD_SPELL` staging file `override/add_spell.ids` should be deleted
   at process exit.
3. **Journal the path.**  The path is appended to `UNINSTALL.<n>` and
   flushed.  This happens before the copy is attempted: the uninstall
   journal entry for a path exists even if every later step fails.
4. **File exists → make the copy.**  The backup copy is created with
   `Util.copy_large_file` ("creating a backup").  Its name inside the
   component dir is the plain basename (`x.2da`) unless a file with
   that name already exists there — two paths with the same basename,
   e.g. `override/x.2da` and `data/x.2da` — in which case the full
   path is flattened by replacing `/`, `\` and `:` with `.`
   (`override.x.2da`).  Whichever name wins is recorded as a
   `path<TB#"SPACE">copy` pair in `MAPPINGS.<n>`, flushed, so the
   restore never has to guess.
5. **File does not exist → journal only.**  No copy is made.  An
   `UNINSTALL.<n>` entry with no backup copy means "this file did not
   exist before the component" — on uninstall the file is deleted,
   not restored.

Nothing is backed up for files a component merely reads.  `BUT_ONLY`
/ `BUT_ONLY_IF_IT_CHANGES` constraints run before the write path, so
files the component decides not to write are never journaled either.

### Which actions reach the choke point, and when

| Action | Route | The moment |
|---|---|---|
| `COPY`, `COPY_EXISTING`, `COPY_EXISTING_REGEXP` | `open_for_writing_internal` with the action's backup flag (`src/tpaction.ml`) | when the output channel is opened, i.e. after patching and constraints; `copy_at_end` may defer the whole write to the end of the action |
| `COPY_LARGE` | `Util.backup_if_extant` then `Util.copy_large_file` | immediately before the streamed copy |
| `EXTEND_TOP`/`EXTEND_BOTTOM`, `COMPILE` (.baf/.bcs/.dlg) | the serializers open their outputs through `Util.open_for_writing` (`src/parsewrappers.ml`) | when the serialized script/dialog is written |
| `APPEND` family | `open_for_writing_internal` with the action's backup flag | when the output channel is opened |
| `MAKE_BIFF`, `DISABLE_FROM_KEY` | new `.bif` (`src/biff.ml`) and `chitin.key` via `open_for_writing` | immediately — these are the only key/biff writes |
| `DELETE` | `Util.backup_if_extant` then unlink | immediately before the deletion |
| `MOVE` | rename + `src<TB#"SPACE">dst` pair into `MOVE.<n>` | at rename time; if the destination exists, the action falls back to `COPY_LARGE` and takes the backup path instead |

### Opting out: the `+` prefix

`COPY`, `COPY_EXISTING`, `COPY_EXISTING_REGEXP`, `COPY_LARGE`,
`APPEND`/`APPEND_*`, `MOVE` and `DELETE` accept a `+` prefix
(`optNoBackup` in `doc/base.tex`).  Then no copy is made: the path is
recorded in `OTHER.<n>` instead (and the trace/log marks the write
`NO BACKUP MADE!`).  `OTHER.<n>` is deleted unread at uninstall — it
exists so external tooling and traces can see the operations, not so
WeiDU can undo them.  A `+`-written file is therefore deleted outright
on uninstall, with no restore.

### The deliberate exception: the TLK files

`STRING_SET`/`SET_STRING` mutate the tlk arrays in memory and record
undo triples in `UNSETSTR.<n>`; the tlk files themselves are only
serialized at the end of the run, after the per-component bookkeeping
channels have been closed and `Util.backup_dir` has been reset to
`None` (`src/main.ml` wrap-up).  A tlk write therefore never reaches
`UNINSTALL.<n>` and never gets a backup copy — the whole-file restore
route does not exist for tlk.  The undo route is `uninstall_strset`
restoring the recorded strings in place, and strings *appended* to the
tlk (by `SAY` and friends) are never removed at all.

### The `--backup` CLI flag

`--backup X` presets `Util.backup_dir` (`src/main.ml`).  It matters
for the one-shot tool modes (decompile, `--out`, `--tlkout`, ...) whose
writes also run through `open_for_writing`; during a normal install
`Util.set_backup_dir` overrides it per component.

### When backups cannot be made

If the bookkeeping files cannot be opened, the run prints
`WARNING: unable to open [...]: ... Will be unable to UNINSTALL later.`
and continues — the component installs, but nothing was journaled, so
it cannot be uninstalled later.  A failing copy aborts the action
(`ERROR: error copying [%s]` and re-raise).

## How uninstall restores

### Who decides what

Two sources with strictly separate roles:

- `WeiDU.log` — the journal of components: `(tp2, language, index,
  name, status)` records parsed by `Parsewrappers.load_log`.  It
  decides *which components* are installed and in what order.  It is
  rewritten (not appended) after each TP2 is processed
  (`Tpstate.save_log`).
- the backup dir — the journals decide *which files* to restore or
  delete for a given component.  WeiDU never scans backup dirs to
  discover anything; `OTHER.<n>` is the one file that is never read
  back.

The TP2 file itself must still exist and parse: `Tpuninstall.uninstall`
(`src/tpuninstall.ml`) locates it via the CLI path or the path recorded
in the log, and a parse failure produces
`ERROR: This Mod is too old (or too new) to uninstall that component
for you.`  Note that the component dir is computed from the *current*
parse's `Tp.backup` — if the mod's `BACKUP` header changed since the
install, WeiDU looks in the new place.

### Entry points and stack uninstall

A component is uninstalled by answering `U` (or `R`, which uninstalls
first) in the interactive menu, by `--uninstall` (which makes `U` the
default answer for every installed component of the queued TP2s), or
by `--force-uninstall N` / `--force-uninstall-list N M ...`
(`src/tpwork.ml` menus, `src/main.ml` flags).  `weinstall` is only a
wrapper that computes the TP2 name and passes flags through.

`Tpuninstall.uninstall` walks the log **newest first** (`List.rev` of
the install order).  Every installed component it meets *before*
reaching the target — i.e. every component installed later than the
target — is temporarily uninstalled first, non-interactively
(`We must temporarily uninstall [%s] component %d.`), then the target
itself is uninstalled with the caller's interactivity, and older
entries are left untouched.  At the end of the run `Tpwork.handle_tp`
reinstalls every `Temporarily_Uninstalled` component in one
non-interactive pass, replaying `READLN.<n>`/`ARGS.<n>`, and appends
the fresh records to the log.

The newest-first discipline is what makes overwriting chains correct.
If component `A` (older) overwrote `x.bcs` and component `B` (newer)
overwrote it again, then `B`'s backup copy holds `A`'s state and
`A`'s backup copy holds the true original.  Uninstalling `A` directly
would stamp `x.bcs` with the original, silently destroying `B`'s
edits; uninstalling `B` first restores `A`'s state, and then `A`'s
uninstall restores the original from *its* copy.

### Replay order inside a component

`Tpuninstall.uninstall_tp2_component` reads the component dir of the
target and replays four action classes, ordered by
`Tpuninstall.validate_uninstall_order`: default
`MOVE → STRSET → COPY → AT`, reorderable by the TP2 `UNINSTALL_ORDER`
flag (a mismatch prints `WARNING: some UNINSTALL_ORDER commands are
not specified`).

- **MOVE** — `uninstall_move` reads `MOVE.<n>` and renames each `dst`
  back to its `src`, printing `WARNING: unable to restore [%s]` per
  failure.  `MOVE.<n>` is then deleted.
- **STRSET** — `uninstall_strset` reads `UNSETSTR.<n>` (binary, with
  `.TEXT` fallback) and `TLKPATH.<n>`; each recorded
  `(strref, male, female)` triple is written back into the in-memory
  tlk pair, which is marked modified and re-serialized at the end of
  the run.  Without `TLKPATH.<n>` on an Enhanced Edition game, WeiDU
  asks for the language directory interactively.  `UNSETSTR.<n>`,
  its `.TEXT` and `TLKPATH.<n>` are deleted after use.
- **COPY** — the core restore, `uninstall_copy`:
  1. read `UNINSTALL.<n>` and reverse it into chronological order;
     print `Will uninstall %3d files for [%s] component %d.`;
  2. read `MAPPINGS.<n>` into a table; an unreadable or missing file
     switches to fallback naming (below); both journals are deleted
     after the loop;
  3. per path:
     - `check_pre_hooks`: for `OVERRIDE/SPELL.IDS`, write the
       per-component `spell.ids.<mod>.<n>.marker` (needed by the
       end-of-run `add_spell.ids` cleanup when the component will be
       reinstalled later in the same run);
     - **unlink the current file unconditionally**;
     - if the mapping table has the path: recreate the directory if
       needed (`ensure_dir`) and restore —
       `Util.copy_large_file` from the recorded copy
       (`  Restoring backed-up [%s]`, reason `restoring a backup`),
       then **unlink the copy**: backup copies are consumed, not kept;
     - else (no mapping, or the component dir predates reliable
       mappings): try the plain-basename copy, then the
       flattened-full-path copy; either restores as above;
     - if no copy exists anywhere: the file stays deleted — this is
       exactly the "created new" case of install time;
     - per-file exceptions are swallowed (`with _ -> ()`): a failed
       restore leaves the file deleted and the uninstall continues;
     - `check_post_hooks`: restoring `CHITIN.KEY` reloads the key and
       drops the cached biff handles, so later lookups re-resolve
       against the restored state.
- **AT** — `uninstall_at` re-parses the component (memoized TP2
  cache), re-sets `%LANGUAGE%` and `%COMPONENT_NUMBER%`, and runs
  `handle_at_uninstall`: `AT_UNINSTALL` always, `AT_INTERACTIVE_...`
  only when interactive, with the `_EXIT` variants queued for process
  exit.  `UNINSTALL ~other.tp2~ N` enqueues that TP2 into the same
  run; a `TP_Biff` inside reloads `chitin.key` first.

### Cleanup

`OTHER.<n>` is deleted unread when the component dir is opened for
uninstall.  Every other bookkeeping file is deleted as it is consumed.
After a successful replay, an **interactive** uninstall additionally
deletes `READLN.<n>`/`ARGS.<n>` (and their `.TEXT` variants), removes
the component dir if it is now empty, and removes the backup root if
that became empty.  A non-interactive (stack) uninstall deliberately
keeps the component dir — the pending reinstall still needs
`READLN.<n>`/`ARGS.<n>` — and the same empty-dir cleanup runs when a
temporarily-uninstalled component is instead finalized as permanently
uninstalled.

Game directories are never removed by uninstall: `ensure_dir` only
recreates them for restores, and directories a mod created are left
behind (empty or not).

### Rollback is the same machinery

A failed install replays immediately: `Tpwork.rollback_component`
closes the component's bookkeeping channels, records
`UNSETSTR.<n>`/`TLKPATH.<n>` for whatever `STRING_SET`s ran, and calls
`Tpuninstall.uninstall_tp2_component` on the component that just
failed.  The log entry is never added, so the failed component is not
uninstallable afterwards — there is simply nothing left.  Any
`--safe-exit` checkpoint (`save_log` right after the component
started) is what makes the rollback state durable across a crash.

## Edge cases and limits

- **No verification anywhere.**  Restores blindly overwrite: no
  checksums, timestamps or content comparison are kept or checked.
  The stack-uninstall discipline is the only protection against one
  mod clobbering another's edits.
- **Component identity comes from the log, not the dir.**  The
  component index used to form `<backup root>/<n>` is the one recorded
  in `WeiDU.log`; directory listings are never consulted.  A component
  that is not in the log ("can't uninstall the non-installed
  component") or was installed with `NOT_IN_LOG` cannot be
  uninstalled at all.
- **Missing pieces degrade, they do not abort.**  A missing
  `MAPPINGS.<n>` switches to basename/flattened-name lookup; a missing
  backup copy leaves the journaled file deleted (correct for created
  files, destructive if a copy was lost); only an unreadable
  `UNINSTALL.<n>` itself aborts the component with
  `Error Uninstalling [%s] component %d:`.
- **`OTHER.<n>` is never read back**; `NO BACKUP MADE!` operations are
  unrecoverable by design.
- **`--safe-exit`** forbids `--force-uninstall-*` and stack uninstalls
  outright (`--safe-exit and --force-uninstall-* are not compatible`,
  `Cannot perform stack uninstalls in --safe-exit mode`).
- **The tlk append-only gap**: appended strrefs survive uninstall;
  only `STRING_SET`-style in-place edits are reverted.

## Observing with `--trace fs`

The backup machinery is highly visible to the filesystem trace
(`doc/trace/execution/README.md`):

- every backup-mode write opens with a `file_write_open` event whose
  `backup` flag is set; `+`-prefix writes open with it clear;
- backup copies appear as `file_copy` events with reason
  `creating a backup` (into the component dir) and `restoring a
  backup` (out of it); `COPY_LARGE` copies carry reason
  `doing a COPY_LARGE`;
- `file_delete` and `file_move` carry the originating action's backup
  flag — a `file_delete` with `backup: 1` is `DELETE` of a backed-up
  file, with `backup: 0` a `+`-prefixed or created-new deletion;
- closing a bookkeeping channel emits a `file_write` with
  `kind: bookkeeping` and a role detail naming the journal
  (`UNINSTALL`, `MAPPINGS`, `MOVE`, `OTHER`, plus `TLKPATH`, `ARGS`
  and `READLN`), sized to the journal's final contents; the
  per-entry appends inside the run are *not* individually traced;
- creation of the component dir itself (`Util.recursive_mkdir`) is not
  traced — a known gap listed in the trace feature doc.

## Flow diagram

```text
install, per component (Util.set_backup_dir):
  <backup root>/<n>/UNINSTALL.<n>   journal: every touched path (flushed per entry)
  <backup root>/<n>/MAPPINGS.<n>    journal: path -> backup copy name
  <backup root>/<n>/MOVE.<n>        journal: src -> dst renames
  <backup root>/<n>/OTHER.<n>       journal: no-backup ops (never read back)

  COPY/EXTEND/APPEND/... -> open_for_writing -> Util.backup_if_extant
      first touch of a path, file exists
          -> copy into <n>/ (basename, or flattened on collision)
          -> MAPPINGS.<n> pair, flushed
      first touch of a path, file absent
          -> UNINSTALL.<n> entry only  (uninstall will delete it)

  STRING_SET -> in-memory tlk edit + UNSETSTR.<n> triple
                (tlk serialized end of run, after journals close: never backed up)

uninstall, per component (Tpuninstall.uninstall_tp2_component), default order:

  MOVE.<n>   -> rename each dst back to src
  UNSETSTR.<n> + TLKPATH.<n>
             -> restore tlk strings in memory; re-serialized end of run
  UNINSTALL.<n> + MAPPINGS.<n>, per journaled path:
                 unlink current file
                 ├─ mapping hit        -> restore copy, consume copy
                 ├─ no mapping         -> try basename, then flattened name
                 └─ no copy anywhere   -> file stays deleted
  AT_UNINSTALL actions re-walked (may enqueue other TP2s)

  interactive uninstall: READLN/ARGS deleted, empty component dir and
  backup root rmdir'ed; stack uninstall keeps them for the reinstall pass
```
