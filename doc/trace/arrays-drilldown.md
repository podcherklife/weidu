# Arrays drilldown: the `$name(keys)` construct and the registry

This document is a drilldown of WeiDU's array system: the `$name(keys)`
"array construct", how it relates to the plain variable store, and what
the array operations (`DEFINE_ARRAY`, `PHP_EACH`, `SORT_ARRAY_INDICES`,
`CLEAR_ARRAY`, ...) actually do.  It complements
`doc/trace/variables-drilldown.md` — arrays are not a separate data
structure but two synchronized views over that store, and nearly every
array surprise is an operation that touches only one of the two views.

As in the other drilldowns, each claim names the module that implements
it (`src/var.ml`, `src/tppe.ml`, `src/tppatch.ml`,
`src/trealparserin.in`), and the behaviors marked *verified* were
exercised against a real install run.

## Notation

- **element** — an ordinary variable whose name is the underscore-join
  of an array name and its keys: `$fruit(1)` *is* the variable
  `%fruit_1%`; `$grid(1 2)` *is* `%grid_1_2%`.
- **registry** — the per-frame table `Var.arrays` (and its `GLOBAL`
  twin `Var.global_arrays`), mapping an array name to a list of
  index tuples (`"fruit" → [["2"]; ["1"]; ["0"]]`).  It holds *no
  values* — only which key tuples have been assigned.
- **accessor** — the `$name(keys)` syntax itself, usable as an
  assignment target or a value in expression positions.
- **flattened name** — the element's variable name as text.

## Two views of one store

An array is nothing but a naming convention plus a bookkeeping table:

- The **element view** lives in the ordinary variable store.  Every
  element is a plain `Int32`/`String` variable in the *current frame*,
  written by the same `Var.set_int32`/`Var.set_string` calls as any
  other variable (`src/tppatch.ml`, `src/tpaction.ml`).
- The **registry view** (`Var.arrays`, `src/var.ml`) records which
  key tuples exist.  Registration happens in `Tppe.PE_Dollars` only
  when the accessor appears in an *assignment* position — the grammar
  encodes this as three separate nonterminals
  (`src/trealparserin.in`):
  - `Patch_String_Left` (assignment targets, `INT_VAR`/`STR_VAR`
    declaration lists) — keys are **registered**;
  - `Patch_String_Right` (value positions) — keys are **read, never
    registered**;
  - `Patch_String_Name` (pure name positions, e.g. the function-side
    name of a `RET x = y`) — neither.

Everything the array machinery does beyond plain variables is
registry-driven.  The split has consequences that a reimplementation
invariably gets wrong, so they are worth stating as observed facts:

1. **Reading is registry-free.**  `$fruit(1)` (right-hand side) and
   the plain `%fruit_1%` substitution read the same variable; neither
   creates or registers anything.  *Verified*: after
   `ACTION_DEFINE_ARRAY fruit BEGIN ~apple~ ~banana~ ~cherry~ END`,
   both read `banana`.
2. **A plain write to the flattened name modifies the element.**
   `OUTER_SET fruit_1 = 99` is an ordinary variable write whose key
   happens to equal the element's name — the next accessor read and
   the next `PHP_EACH` iteration both see `99`.  *Verified.*  This is
   the user-visible side of "arrays are flattened variables in the
   current scope": any code that can compute the flattened name can
   bypass the accessor entirely.
3. **A plain write to a *new* flattened name creates an element the
   registry cannot see.**  `OUTER_SPRINT fruit_9 ~nine~` creates
   `%fruit_9%`, but `VARIABLE_IS_IN_ARRAY $fruit(9)` is false and
   `PHP_EACH` will not enumerate it — both check the registry, not
   the store.  *Verified.*  Conversely, an accessor write
   (`OUTER_SPRINT $extra(5) ~hello~`) registers and enumerates
   normally.  *Verified.*
4. **Membership outlives value changes.**  Overwriting a registered
   element through its plain name keeps it in the registry (the
   write touches only the variable); `fruit` keeps iterating keys
   `0 1 2` with the new value.  *Verified.*
5. **The two views can therefore disagree forever.**  After the
   above, `fruit_9` exists, is readable, is substitutable — and is
   invisible to every array operation until something registers it.

### Reading a missing key

An accessor read of a key with no element falls back like an
undefined variable — but at the *joined-name* layer
(`Tppe.PE_Dollars`, `do_eval` branch: integer parse of the joined
name, then `Var.get_string_exact` of `%name%`, else the joined name
itself):

- `OUTER_SPRINT zz $fruit(77)` yields the text `fruit_77` —
  *verified*;
- the plain `%fruit_77%` substitution yields the literal
  `%fruit_77%` — *verified*.

Same underlying rule ("undefined passes through"), two different
literal results.

## Syntax facts

- Keys are **space-separated** inside the parens: `$var(a b c)`
  (`doc/base.tex`, the array-construct tutorial).  A comma is not a
  separator in accessor key lists — `OUTER_SET $grid(1,2) = 5`
  fails to parse (*verified*), while `OUTER_SET $grid(1 2) = 5` is
  accepted.  The one place commas are legal is the key list of a
  `DEFINE_ASSOCIATIVE_ARRAY` pair (`~1~,~2~ => ~v~`, grammar
  `Array_Parameter_List`).
- Keys are evaluated as strings and joined with `_` — a key may be a
  bare word, a `~quoted~` string, or a `"%var%"` form whose value is
  substituted first (`SPRINT $kitlist("%kit%") ...` from the manual).
  Numeric-looking keys are just strings: `$fruit(1)` and `$fruit(01)`
  are different elements.
- The accessor is a **grammar construct, not a substitution**:
  inside `~...~` text, `$fruit(0)` is literal characters.  Strings
  reach elements only via `%fruit_0%`; expression positions reach
  them via the accessor.
- Assignment forms: `OUTER_SET`/`SET` are int-only; string elements
  are written with `OUTER_SPRINT`/`SPRINT` — both take an accessor
  LHS and register it.

## Creation paths

All of these end in the same place — flattened variables plus, for
the registry-creating ones, registry entries:

| Construct | Elements written | Registered? |
|---|---|---|
| `DEFINE_ARRAY`/`ACTION_DEFINE_ARRAY name BEGIN v0 v1 ... END` | `%name_0%`, `%name_1%`, ... | yes, in order |
| `DEFINE_ASSOCIATIVE_ARRAY`/`ACTION_...` `BEGIN k => v ... END` | `%name_k%` (keys may be comma-separated key lists → 2D) | yes |
| accessor assignment (`OUTER_SET $n(k) = ...`) | the one element | yes |
| plain variable write (`OUTER_SET n_k = ...`) | the one element | **no** |
| `GET_FILE_ARRAY`, `GET_DIRECTORY_ARRAY`, `GET_RESOURCE_ARRAY`, `GET_OFFSET_ARRAY` | key → value elements | yes |

`PHP_EACH` over the two dictionary forms iterates key tuples; the
loop binds the key variable to the tuple's *first* key and declares
`key_0 ... key_n` locals with the full tuple (removed after each
iteration, `TP_PatchPHPEach`, `src/tppatch.ml`).  *Verified* on a 2D
element: `k=1`, `k0=1`, `k1=2`.

## Iteration and ordering

- Registration **prepends** (`Hashtbl.add`), so the stored tuple list
  is in reverse-definition order; `TP_PatchPHPEach` iterates
  `List.rev values`, so `PHP_EACH` walks arrays in **definition
  order**.  *Verified*: keys `0 1 2`.
- `SORT_ARRAY_INDICES` sorts **indices, not values**
  (`TP_PatchSortArrayIndices`): `NUMERICALLY` compares the first key
  of each tuple as an integer; `LEXICOGRAPHICALLY` (the default, when
  the sort keyword is omitted) compares the flattened element *names*
  with plain byte order — which for numeric keys gives the famous
  `10 < 100 < 9` ordering.  *Verified* on keys `10 9 100`:
  `NUMERICALLY` → `9 10 100`; `LEXICOGRAPHICALLY` → `10 100 9`.
- Sorting re-stores the tuple list with another `Hashtbl.add` — a
  shadow entry; the old order remains underneath, which is why
  `CLEAR_ARRAY`'s removal is a `while Hashtbl.mem ... remove` loop:
  `Hashtbl.remove` in the bundled hashtable backport drops only the
  most recent binding per call (see
  `doc/trace/variables-drilldown.md`).  *Verified*: sorting twice
  flips the iteration order between the two modes with no residue.

## Scopes and GLOBAL

- Elements and registry are both part of the frame, so
  `Var.var_push`'s snapshot semantics apply to arrays exactly as to
  variables: a `WITH_SCOPE`-created element (`$sc(3)`) and its
  registration both vanish at pop.  *Verified*: the element reads as
  literal `%sc_3%` afterwards.
- `GLOBAL` writes both views to the global twins: the element into
  `Var.global_scope`, and — via the `global_push_arrays` registry
  swap bracketing the accessor-name evaluation (`src/var.ml`) — the
  registration into `Var.global_arrays`.  Both survive the scope.
  *Verified*: `OUTER_SPRINT GLOBAL $gg(3) ~kept~` inside `WITH_SCOPE`
  reads back and iterates afterwards.
- `RET_ARRAY` snapshots the function frame's registry entries and
  element values before `var_pop` and re-creates them under the
  caller's name afterwards (`TP_Launch_Patch_Function`,
  `src/tppatch.ml`).  Elements that exist but were never registered
  are silently dropped by this path — the registry, again, is the
  source of truth.

## Clearing

- `CLEAR_ARRAY name` / `ACTION_CLEAR_ARRAY name` empties the *name's*
  registry entries only — and only in whichever registry the name
  currently lives in (`Var.array_lookup` returns a global flag).  The
  elements (`%fruit2_0%` ...) survive as ordinary variables.
  *Verified.*
- `CLEAR_ARRAYS` (`Var.clear_arr`) empties the whole registry of the
  current frame only — same caveat, all element variables survive.
  *Verified.*  Nothing but the elements' own names remembers them;
  they are re-enumerable only after something re-registers the keys.
- Neither operation ever touches `Var.global_scope`, so `GLOBAL`
  element values survive both (their registration survives
  `CLEAR_ARRAYS` too, living in `Var.global_arrays`).

## Divergences a reimplementation gets wrong

| Expectation | WeiDU reality |
|---|---|
| An array is a container | Two views: flattened variables (values) + a registry (key tuples).  Operations touch one or the other |
| Iterating sees all elements | `PHP_EACH` sees registry entries only; plain-created elements are invisible |
| Writing through the array API is the only path | Any plain write to the flattened name modifies the element — and skips registration |
| Membership implies existence | An element can exist without membership, and (after clearing) membership entries can be emptied while elements persist |
| Clearing deletes data | Clearing deletes only registry entries; values survive |
| Sorting orders values | `SORT_ARRAY_INDICES` orders *keys*; lexicographic mode compares flattened names in byte order |
| Arrays are contiguous/indexed | Keys are arbitrary strings joined with `_`; `$fruit(01)` ≠ `$fruit(1)` |
| Invalid key read is an error or empty | Yields the flattened name as text (`$fruit(77)` → `fruit_77`); the plain `%fruit_77%` yields `%fruit_77%` |
| Multi-key syntax is uniform | Accessor keys are space-separated; only `DEFINE_ASSOCIATIVE_ARRAY` pair keys take commas |
| Array values are typed | Elements are ordinary Int32/String variables — last write wins, exactly like variables |

## Observing

- `--debug-assign` shows element writes as ordinary `SET`/`GET`
  lines on the flattened names (`SET %fruit_1% = 99`) — the clearest
  way to see the element view.
- `PRINT` can show values via `%flat-name%` substitution; accessor
  reads must go through a real expression position (`OUTER_SPRINT x
  $fruit(1)`).
- `PHP_EACH ... PRINT` is the direct window onto the registry view —
  anything it does not print is not registered.
- Nothing here is filesystem-visible; `--trace fs` has no array
  events (the store is memory-only).

## Flow diagram

```text
                    $name(keys)  accessor
                    /                     \
   assignment position                value position
   (Patch_String_Left)                (Patch_String_Right)
        |                                    |
        v                                    v
  write element variable           read element variable
  %name_k1_k2%  (plain Var.set_*)  (Var.get_string_exact of the
        |                           flattened name; missing key
        v                           yields the flattened name)
  REGISTER key tuple  ──────▶  Var.arrays[name]  (prepend; reversed)
        |                             |
        |                             +-- PHP_EACH  (List.rev: definition order)
        |                             +-- VARIABLE_IS_IN_ARRAY (membership test)
        |                             +-- RET_ARRAY snapshot (function return)
        |                             +-- SORT_ARRAY_INDICES (sorts tuples!)
        |                             +-- CLEAR_ARRAY / CLEAR_ARRAYS (drop tuples,
        |                                 element variables survive)
        |
  plain write to %name_k1_k2% (no accessor): modifies the element,
  touches NO registry  ──▶ the two views diverge
```
