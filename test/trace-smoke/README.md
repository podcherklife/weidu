# Trace smoke fixture

The fixture deliberately keeps the operation set small:

- `COPY` performs a local `file_read` and a `file_write` (plus
  `file_write_open` for the destination).
- `COPY_EXISTING ~ANIMATE.IDS~` performs a semantic `resource_read` from the
  game's BIFF/KEY data and writes a copy under `override/`.

It does not compile BCS/DLG files, touch the TLK, or run any remove/move
actions. That keeps the first trace comparison focused on the hooks listed in
`notes/trace-instrument-now.md`.

## Run from the game root

Copy this directory to `$GAME/trace-smoke`, then from `$GAME`:

```sh
/path/to/build/weidu-augmented \
  --noautoupdate \
  --use-lang en_US \
  --force-install 0 \
  trace-smoke/trace-smoke.tp2
```

For the traced run, add `--trace aug-smoke.jsonl`. Relative trace paths are
resolved against the TP2 directory, so this lands in `trace-smoke/`; use an
absolute path if you want the trace elsewhere. Reset the game to the `pristine`
snapshot between the untraced and traced runs.

Expected writes from this fixture:

- `trace-smoke/output.txt`
- `override/trace-smoke-animate.ids`
- `weidu.conf` (game configuration written during load)
- `WeiDU.log`

`BACKUP` may create `trace-smoke/backup/` and its bookkeeping files. Those
bookkeeping files are not traced yet; exclude them when comparing the first
fixture's expected writes against the trace. The trace file itself is also not
part of the installed output; with `--trace aug-smoke.jsonl` it appears inside
`trace-smoke/`, so exclude it from the comparison too.

## Smoke-run observations

An untraced run and a traced run both succeeded on 2026-10-28, and the SHA-256
hashes matched for the output, override file, `weidu.conf`, `WeiDU.log`, and
backup files. The trace covered the local payload read, `ANIMATE.IDS` as a BIFF
resource, both primary output writes, and the log write.

After the parser/line-reader/config hooks were added, a traced run also recorded:

- the TP2 read through `Util.parse_file` (the parser may open the TP2 more than
  once while trying its parse paths);
- the existing `WeiDU.log` read;
- the `weidu.conf` write through `Util.save_conf`;

Backup bookkeeping remains deliberately deferred. The source hooks for the TP2
read and `weidu.conf` are in `src/util.ml`.

On case-insensitive filesystems, `WeiDU.log` and `weidu.log` resolve to the same
file; normalize the path case when comparing trace paths to a filesystem diff.
