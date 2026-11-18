# Variables drilldown: WeiDU's variable store, scopes, and evaluation

This document is a drilldown of WeiDU's variable model: what the store
looks like, when `%var%` text is substituted, how patch expressions are
evaluated, what scopes exist (and, more importantly, what does *not*
create a scope), and how long values live.  It complements
`doc/trace/architecture-drilldown.md` (whose Phase 5 describes the
environment as part of the action interpreter) and is written for
reimplementation-verification: WeiDU's variable model is small enough
to restate in a paragraph, and every difference between that paragraph
and a conventional language design is a behavioral divergence a
reimplementation is likely to get wrong.  Those divergences are
collected in the [final section](#where-this-diverges-from-ordinary-language-design).

Every claim names the module that implements it (`src/var.ml`,
`src/tppe.ml`, `src/tppatch.ml`, `src/tpaction.ml`, `src/tpstate.ml`).

## Notation

- **variable** — one entry of the store: a name and a value that is
  either an Int32 or a string.
- **frame** — one pair of tables (variables + array registry).  The
  "current frame" is what reads and writes hit; a stack of older
  frames is kept for restoration.
- **substitution** — the textual `%var%` → value pass performed by
  `Var.get_string` on string content.
- **evaluation** — the typed expression walk performed by
  `Tppe.eval_pe` / `Tppe.eval_pe_str` over `tp_patchexp` AST nodes.
- **string positions vs expression positions** — TP2 syntax has
  *string* contexts (`~text~`, `SPRINT`, `EVALUATE_BUFFER`) and
  *expression* contexts (`OUTER_SET`'s RHS, `PATCH_IF` conditions,
  `READ_*`'s value).  Substitution happens in string contexts;
  evaluation in expression contexts.  Much of the arcane behavior
  below comes from these two worlds meeting.

## The store

`src/var.ml` is the entire store:

- Values are a two-constructor variant, `Int32 of Int32.t` or
  `String of string`.  There is one table for both; **the last write
  decides the type**.
- Keys are stored *including* the `%` delimiters: every setter wraps
  the name (`Var.var_wrap`, `Var.set_int32`, `Var.set_string`).  A
  variable is therefore the literal string `%FOO%`, not `FOO`.
- Names are **case-sensitive and otherwise unnormalized** — no
  uppercasing, no trimming.  `%foo%` and `%FOO%` are different
  variables, in a program whose filesystem layer is aggressively
  case-insensitive.
- Alongside the current frame (`Var.variables`) there is a **global
  scope** (`Var.global_scope`, written by `GLOBAL`) consulted on
  lookup miss (`Var.var_lookup`).  It is never copied, pushed, or
  cleared by the frame machinery — only `CLEAR_MEMORY` and process
  exit touch it.
- **Arrays are not containers.**  There is no array value type.  An
  array element `$name(k1,k2)` is just a variable whose name is the
  underscore-join `name_k1_k2` (`Tppe.PE_Dollars`, `src/tppe.ml`),
  plus a separate registry table (`Var.arrays` mapping the array name
  to a list of index tuples) that exists only so `PHP_EACH`,
  `VARIABLE_IS_IN_ARRAY`, `RET_ARRAY` and friends can enumerate
  elements.  Registering happens when the flattened name is used in
  an *assignment* position; reading an element never registers it.
  The element/registry split and everything built on it is
  documented in `doc/trace/arrays-drilldown.md`.
- The hashtable is the bundled OCaml 4.03 backport
  (`hashtbl-4.03.0/myhashtbl.ml`), whose semantics matter: `add`
  **prepends**, so `find` returns the most recent binding — but
  `replace` and `remove` touch **only that most recent binding** (the
  bucket walk stops at the first match).  Older same-key bindings,
  created by shadowing `add`s, keep their values and resurface when
  the newest one is removed.  The macro machinery (below) is built on
  exactly this trio.

### Engine-seeded variables

At process start (`Var.all_the_assoc`, plus `Arch2.associate_these`)
the store is seeded with: the CRE creature-field offset constants
(`NAME1`, `ATTACK1`, `BIO`, `SCRIPT_OVERRIDE`, ... — about 60 of
them), `BIT0`–`BIT31`, the newline constants `WNL`/`MNL`/`LNL`/`TAB`,
and the registry paths `REGISTRY_<GAME>_PATH`; plus `WEIDU_ARCH`,
`WEIDU_OS`, `WEIDU_VER`.  Game context adds
`SAVE_DIRECTORY`/`MPSAVE_DIRECTORY`/`USER_DIRECTORY`/`EE_LANGUAGE`;
per TP2, `TP2_AUTHOR`/`TP2_FILE_NAME`/`TP2_BASE_NAME`/`MOD_FOLDER`/
`MOD_VERSION` (`Tpstate.set_tp2_vars`); per component, `LANGUAGE`,
`COMPONENT_NUMBER`, `INTERACTIVE`, `WEIDU_EXECUTABLE`; per COPY,
`SOURCE_*`/`DEST_*`/`SOURCE_SIZE` (`Tphelp.set_copy_vars`); per
`BASH_FOR` iteration, `BASH_FOR_*`; per `REPLACE_EVALUATE` match,
`MATCH0`–`MATCH200`; per `TRY`, `ERROR_MESSAGE`.

One subtle seed detail with real consequences: the CRE offset
constants are stored under **unwrapped** keys (`assoc` writes
`Hashtbl.replace !variables "NAME1"` — no `%` delimiters,
`src/var.ml`).  They are therefore *invisible to substitution*:
`~%NAME1%~` stays the literal text `%NAME1%`.  They are readable only
in expression positions, through the int-context fallback chain
(below).

## Substitution: strings are templates

String content is a template evaluated at the moment of use, by
`Var.get_string` (`Var.get_string_special` with the fixed regexp
`%[^%]+%`):

- **One pass, non-recursive.**  `Var.var_subst` walks the string once;
  each match's replacement is appended to the output buffer and never
  re-scanned.  A pass turns `%%x%%` into `%<value of x>%` — the inner
  `%x%` matches, the outer delimiters survive as literal text.
- **Undefined variables pass through silently.**  A match that
  resolves to nothing is copied through one character at a time with
  no warning: `~undef=[%nope%]~` yields `undef=[%nope%]`.  WeiDU
  itself exploits this "output == input when nothing resolves"
  property: `%argv[N]%` probing (`Tpwork.handle_cli_vars`) stops at
  the first index that fails to shrink, and the `MISSING_EVAL` modder
  lint (`Tphelp.check_missing_eval`) flags argument strings that
  still contain `%...%` after evaluation as a probable missing
  `EVALUATE_BUFFER`.
- **Int values render as decimals** (`Int32.to_string`) in string
  context; string values render as-is.  An int read of a string
  variable is the other direction: `Var.get_int32` does
  `Int32.of_string` and raises on non-numeric content.
- **Escaping is `%%`-layering plus nothing.**  There is no escape
  character; the only way to *delay* substitution by one round is to
  wrap a name in double percents and force a second pass (below).

### Multi-pass substitution is layering, not recursion

A single `Var.get_string` never re-scans.  Multiple passes happen
only when evaluation layers two substitution sites.  The canonical
indirection idiom:

```text
OUTER_SPRINT x ~y~                        ; x holds a variable NAME
OUTER_SET  y = 42
OUTER_SPRINT w ~[%%x%%]~                  ; one pass:  w = "[%y%]"
OUTER_SPRINT z EVALUATE_BUFFER ~[%%x%%]~  ; pass 1 inside EVALUATE_BUFFER: "[%y%]"
                                          ; pass 2 in SPRINT itself:   z = "[42]"
```

`EVAL`/`EVALUATE_BUFFER` in a string position (`Tppe.PE_Evaluate`)
performs exactly one `Var.get_string` of the evaluated inner string;
the consuming op then performs its own.  The TP2 flag
`AUTO_EVAL_STRINGS` automates such a pass for literals: with it,
`PE_LiteralString` substitutes its own content once, so every
`~...~` gets a pass even where none would otherwise happen.

Three more substitution entry points, all one-pass:

- `EVALUATE_BUFFER` as a standalone patch op rewrites the *whole file
  buffer* with one substitution pass before further patches run
  (`TP_EvaluateBuffer`, `src/tppatch.ml`); `COMPILE ... EVALUATE_BUFFER`
  does the same to a `.d` source before parsing.
- `EVALUATE_BUFFER_SPECIAL ~c~` substitutes with a custom
  single-character delimiter `c...c` instead of `%...%`; when the
  delimiter is not `%`, a lookup fallback still tries the matched
  text stripped and re-wrapped in `%...%`, so `~foo~` finds variable
  `%foo%` (`Var.get_string_special`'s non-default-regexp branch).
- `Var.get_string_exact` reads a variable **without substituting its
  content** — used wherever the raw value must not be re-expanded:
  `RET` capture, `PE_GetVar` (bare argument names in `LAF`/`LPF`
  calls), and `TOLOWER`/`TOUPPER` helpers.

**Substituted values are never re-parsed as code.**  `src/tppe.ml`
contains no parser call on substitution results; expression structure
is fixed at TP2-parse time.  If `e = "1+2"`, then
`OUTER_SET n = EVAL ~%e%~` substitutes to the *text* `1+2`, which the
int context then fails to parse (`ERROR: cannot convert 1+2 or
%1+2% to an integer`, observed verbatim).  Text flows through
substitution; syntax does not.

## Evaluation: expressions are integer-shaped

`Tppe.eval_pe` (`src/tppe.ml`) — the evaluator for `tp_patchexp`
nodes, reached from every expression position (`PATCH_IF`, `OUTER_SET`
RHS, `READ_*` values, `WHILE` guards, `FILE_*`/`GAME_IS` predicates) —
**always returns an Int32**.  Strings flow through `Tppe.eval_pe_str`
and per-op `Var.get_string` calls; there is no string-typed
expression result except as the best-effort `Tppe.string_of_pe` view
used by `SPRINTF %s` and `PATCH_MATCH`.

The load-bearing node is `PE_String` (any text in an int context),
whose resolution chain is:

1. parse the substituted text as an integer literal
   (`Int32.of_string`) — this is how bare `5` and how *the decimal
   rendering of a variable* work;
2. look up a variable named `%<text>%`;
3. look up a variable named `<text>` (bare, unwrapped) — this is how
   the CRE offset constants (`NAME1` = 8) are read;
4. fail with `ERROR: cannot convert <s> or %<s>% to an integer`
   (suppressed during probing contexts via `Util.eval_pe_warn`).

Arithmetic and logic facts a reimplementation must copy:

- `+` is Int32 addition — **there is no string concatenation
  operator**; build strings with `SPRINTF`/`SNPRINT`.
- Division and modulo by zero yield `0`, not an error
  (`PE_Div`/`PE_Mod` catch `Division_by_zero`); `**` computes through
  floats and yields `0` on any failure.
- `AND`/`OR` evaluate **both** operands — they are not
  short-circuiting — while the ternary `p ? a : b` is lazy.
- Predicates can have parse side effects: `ID_OF_LABEL` resolves
  through the TP2 cache and will parse *other mods'* TP2 files if
  needed (`Tppe.PE_IdOfLabel`); `GAME_IS`/`ENGINE_IS` results are
  cached in `Var.gameIsCache`-style tables.
- There is **no function-call syntax in expressions**: `$f(args)` is
  array-variable syntax (the flattened name `f_args1_args2`), not a
  call.  Functions are invoked only by the `LAF`/`LPF` statement
  forms (below).
- Compound assignments are parser desugarings, not ops:
  `OUTER_SET x += e` becomes `SET x = x + e` (re-read as int, then
  write), and `FOR (init; guard; inc) BEGIN ... END` becomes
  `init` + `WHILE guard BEGIN ... inc ... END` (`src/tppatch.ml`).

## Scopes: snapshots, not environments

`Var.var_push` implements the only real scope mechanism:

```text
push:  save current tables; variables := Hashtbl.copy variables;
       arrays := Hashtbl.copy arrays
pop:   restore the saved table refs
```

The child frame is a **value snapshot of the parent**.  Consequences,
in order of surprise:

1. **Reads see everything the caller saw** (the copy includes all of
   it) — a function can read any caller variable, declared or not.
   The builtin stdlib even relies on this: `TB#ADD_SPELL_CHECK_MATCH`
   (`src/tph/define/add_spell.tpa`) reads caller variables it never
   declared.
2. **Writes die at pop.**  Nothing a function writes (except `RET`
   captures and `GLOBAL`) escapes its call.  There are no
   out-parameters, no by-reference arguments, no write-through.
3. **`GLOBAL` bypasses frames entirely**: `OUTER_SET GLOBAL x = ...`
   writes `Var.global_scope`, which every frame's lookup falls back
   to and which `var_pop` cannot undo.  It is the sanctioned channel
   for communicating out of a scope without `RET`.
4. Nothing else about the frame is special: there is no "local
   namespace", no closure capture (a stored function body re-reads
   the store at *call* time), and recursion simply stacks snapshots.

### The complete census of scope-creating sites

Every `var_push`/`var_clear_push` call in `src/`:

| Construct | Effect |
|---|---|
| `LAF`/`LPF` (`TP_Launch_Patch_Function`) | function-call frame |
| `WITH_SCOPE`/`PATCH_WITH_SCOPE BEGIN...END` | explicit scope |
| `WRITE_BYTE`/`WRITE_SHORT`/`WRITE_LONG` | scratch frame around the automatic `THIS`/`STHIS` read when the value expression needs it |
| `ADD_JOURNAL` on EE games | frame around its `existing`/`title` helpers |
| log rendering (`Tpstate.sprintf_log`) and `--list-components-json` | `var_clear_push`: fresh *empty* frame so re-parsing other mods' TP2s cannot touch the real store |

**Everything else shares the caller's frame.**  `WHILE`/`FOR` bodies,
`IF`/`ELSE` branches, `PATCH`/`INNER_ACTION`, `BUT_ONLY`, macro
bodies, `OUTER_INNER_PATCH` — none of them push; a variable set
inside any of them outlives the construct.  In particular an
`INNER_ACTION` block inside a patch macro writes straight into the
ambient frame (`src/tph/include/tb#macros.tpa`'s
`tb#fix_file_size` does exactly this on purpose).

### Functions vs macros

Functions (`DEFINE_ACTION_FUNCTION`, `DEFINE_PATCH_FUNCTION`,
`DEFINE_DIMORPHIC_FUNCTION`) and macros (`DEFINE_ACTION_MACRO`,
`DEFINE_PATCH_MACRO`) are stored in `Tpstate.functions` /
`Tpstate.macros`, keyed by `(name, is_patch)`; `LAF` dispatches the
`false` key, `LPF` the `true` one, and a dimorphic definition
registers the same converted body under both keys (whichever of the
three `DEFINE_*` forms came last wins for its key).

**Function call** (`TP_Launch_Patch_Function`, `src/tppatch.ml`):

1. `var_push`;
2. bind passed `INT_VAR`/`STR_VAR` arguments into the new frame,
   **in sequence** — each argument's value expression is evaluated
   after the previous arguments are already bound, so later
   arguments may read earlier ones;
3. fill declared-but-unpassed arguments from their defaults;
4. run the body through the patch engine (an action body is stored
   as `[TP_PatchInnerAction body]` and executes actions inside the
   frame);
5. still inside the frame, snapshot `RET_ARRAY` registries and read
   every `RET` name with `Var.get_string_exact` — **return values
   cross as strings**; int-ness is recovered later by coercion;
6. `var_pop`, then copy the captures into the caller-named targets
   (`Var.set_string`).

A `RET x` whose name was never set in the body does not fail if the
caller or the global scope happens to have `x` (the snapshot
pass-through feeds the caller's own value back); with no binding
anywhere it fails with `Uninitialised return value: x`.  Unknown
`RET_ARRAY` names fail similarly.

**Macros** (`TP_Launch_Patch_Macro`) **push nothing**.  Their
declared locals (`LOCAL_SET`/`LOCAL_SPRINT`/`LOCAL_TEXT_SPRINT`,
written between `BEGIN` and the body) are implemented with
`Var.add_local_*` — a `Hashtbl.add` shadow on the *current* frame —
and `Var.remove_local` after the body.  Given the backport's
first-binding-only `replace`/`remove`, this behaves like a genuine
local:

- the body runs in the caller's frame: every write to a
  *non-declared* name is a caller write (macros are the "returns by
  side effect" construct);
- a declared local *seeds* from any same-named caller variable
  (`find` sees the newest binding);
- a write to a declared name updates only the shadow — the caller's
  binding is untouched — and the trailing `remove_local` drops the
  shadow, resurfacing the caller's value.  Verified end to end:
  caller `loc = 5`, macro declares `LOCAL_SET loc = 0` then `SET
  loc = 77` — inside the macro `loc` reads `77`, after it reads `5`;
- recursion leans on the seeding: the stdlib's `tb#factorial` macro
  (`src/tph/include/tb#macros.tpa`) opens with
  `LOCAL_SET tb#factorial_index = tb#factorial_index`, decrements
  with `-=` (updating the shadow), and recurses; each level seeds its
  shadow from the current value and the unwind pops one shadow at a
  time.

The two macro flavors are separate registries: `LAUNCH_ACTION_MACRO`
looks up `(name, false)` and fails with `Unknown macro: ...` for a
`DEFINE_PATCH_MACRO`-defined body — only dimorphic *functions* share
a body across contexts.

`WITH_SCOPE` is the only deliberate user-scoped construct, and the
stdlib does not use it; its isolation strategy is `tb#`-prefix
naming plus function frames.

## Lifetime: process-global, explicitly reset

- **Across components of one TP2: variables persist.**  Nothing
  between components clears the store; each component merely
  overwrites the engine-set variables (`COMPONENT_NUMBER`, ...).
  Component 0 can leave a variable for component 1.
- **Across TP2 files in one run: persist.**  The queue loop in
  `main.ml` (`do_tp2_files`) processes each TP2 with the same live
  store.  (This is why two mods installed in one invocation can
  observe each other's variables — mod-order dependence is baked
  in.)
- **Across processes: nothing persists.**  The store is never
  written to disk.  The only marshaled variable-adjacent state is
  the `%argv[N]%` list saved into the backup dir's `ARGS.<n>` file
  (`Tpwork.handle_cli_vars`), which a later non-interactive run
  restores so stack-uninstall reinstatements answer consistently.
- **Explicit resets** are TP2 actions, not automatic events:
  `CLEAR_ARRAYS` (`Var.clear_arr`) empties the *registry* only —
  element variables like `%arr_5%` survive; `CLEAR_MEMORY`
  (`Var.clear_var`) empties the frame but **not** `global_scope`, and
  first stashes eleven environment variables and restores them
  *through strings*, which means an Int32 variable among them comes
  back typed as String (harmless at runtime thanks to dynamic
  coercion, but observable); `CLEAR_EVERYTHING` chains arrays +
  memory + inlined files + macros/functions + IDS maps.  The
  `--clear-memory` CLI flag runs `CLEAR_MEMORY` after every action
  evaluation.

## Where this diverges from ordinary language design

The table a reimplementation should treat as its conformance test:

| Ordinary expectation | WeiDU reality |
|---|---|
| Lexical scoping; functions see their parameters only | Dynamic snapshot scoping: a function reads *everything* visible at the call site (frame = `Hashtbl.copy`), and `RET`/`GLOBAL` are the only exits |
| Undefined variable is an error | Silent literal pass-through — `%nope%` stays `%nope%`; WeiDU itself detects "undefined" by comparing substituted text against input |
| Names bind at parse time | Strings are templates evaluated at every use; late binding; the same string can yield different values at different times |
| Interpolation is parsed | Substitution is a single textual pass; replacement text is never re-scanned and never re-parsed as syntax |
| Strong, stable types | One store, two value types, last write wins; int reads coerce with `Int32.of_string`; `RET` values cross as strings |
| `+` concatenates strings | `+` is Int32 addition; string building is `SPRINTF` |
| `&&`/`||` short-circuit | Both operands always evaluate; only `? :` is lazy |
| Arrays are containers | An array is a naming scheme (`name_k1_k2` variables) plus a registry of index tuples; "clearing" empties the registry, not the elements |
| `$f(args)` in an expression calls `f` | `$f(args)` is array-variable syntax; calls exist only as `LAF`/`LPF` statements |
| Division by zero raises | Yields `0` (and `**` yields `0` on any float failure) |
| Function locals isolate invocations | Macro `LOCAL_*` locals are shadow bindings on the caller frame: writes update the newest binding only, and the caller's shadowed value resurfaces after the macro |
| Constants are usable in any context | The CRE offset constants live under unwrapped keys: readable in expressions via the bare-name fallback, invisible to `%...%` substitution |
| Case handling is uniform | Variable names are case-sensitive (everything else in WeiDU is case-insensitive) |
| Automatic reset per unit | The store is process-global: it persists across components and TP2 files of one run, and `CLEAR_MEMORY` stashes environment variables as strings (Int32 comes back as String) |

Two further traps worth calling out in prose:

- **"No substitution" and "empty" look identical from data, not from
  behavior.**  A variable set to the empty string and an unset
  variable both render as empty text; only `VARIABLE_IS_SET` can
  tell them apart, and it checks the store, not the text.
- **Evaluation order is specified by the AST, not the syntax.**  Both
  `AND`/`OR` operands, both `?`-branches' guard, and all argument
  expressions of a call are walked in AST order with the store
  mutating as they go — the "later arguments may read earlier ones"
  rule is an emergent property of sequential binding, not a designed
  feature.

## Observing

- `--debug-assign` (`src/main.ml`) turns on `Var.debug_assign`: every
  `SET`/`LOCAL_SET`/`GLOBAL_SET`/`GET` is logged into the WeiDU log
  (`SET %s = %ld` / `GET ~%s~ = ~%s~`), which makes substitution
  results directly visible.
- The `MISSING_EVAL` modder flag warns when an evaluated string still
  contains unresolved `%...%` text (`Tphelp.check_missing_eval`);
  `FUN_ARGS` warns when `LAF`/`LPF` passes undeclared argument names.
- `PRINT ~...~` (`TP_PatchPrint`, `src/tppatch.ml`) substitutes and
  prints its argument — the direct way to observe a variable's
  rendered value at a given point.
- `--trace fs` is of no help here: the variable store is memory-only,
  and the only file it touches is the `ARGS.<n>` bookkeeping file of
  the backup machinery (`doc/trace/backup-drilldown.md`).

## Flow diagram

```text
string position (template)                expression position (typed)
  ~text with %var%~                         OUTER_SET n = 1 + %k%
       |                                         |
       v                                         v
  Var.get_string (one pass)             Tppe.eval_pe  (always Int32)
  regexp %[^%]+%                            PE_String chain:
       |                                      Int32.of_string text
       +-- defined: append value,             |  fail -> variable %text%
       |   never re-scan the value            |  fail -> variable text
       +-- undefined: copy "%",               |  fail -> ERROR cannot convert
           resume 1 char later                    (constants live at step 3)
       |
  second pass? only via layering:       statements:
  EVALUATE_BUFFER / EVAL = 1 pass,        SET/SPRINT  -> Var.set_* (frame write)
  then the consuming op's own pass        LAF/LPF     -> var_push, bind args in order,
  AUTO_EVAL_STRINGS: literal gets                        defaults, body, RET snapshot,
  one own pass                                           var_pop, assign caller targets
                                          macros      -> no push; add_local shadows,
                                                         body writes caller frame,
                                                         remove_local resurfaces caller value
frames:  push = copy(variables, arrays)   lifetime: persists across components
         reads inherit; writes die at pop   and TP2s; never persisted to disk;
         GLOBAL = global_scope, survives    CLEAR_MEMORY / CLEAR_ARRAYS / --clear-memory
```
