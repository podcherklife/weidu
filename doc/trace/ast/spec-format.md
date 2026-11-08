# The AST Spec Format (`ast-spec.sexp`)

This document specifies `ast-spec.sexp`: a standalone, machine-readable
catalog of the AST shapes that `--dump-ast` emits, together with the exact
wire names those shapes carry in dumps.  It is written for consumers who
**never read the WeiDU sources**: a reimplementation generates its AST
framework from this file and uses the same file to interpret and validate
dump output.

## Purpose and ownership

The spec is the **source of truth for AST structure**.  The WeiDU binary
is a *reference implementation*: it remains the behavioral oracle (run it
on any input, compare dumps), but nothing in this file may be derived
from, or checked against, the OCaml sources as a matter of course.

- **Structures** live here: every type, constructor, field, and scalar
  that can appear in a dump, closed-world.
- **Behaviors** (how source text becomes a tree, how trees execute) are
  *not* specified here.  They are pinned by the frozen oracle binary and
  the golden corpus, and are a separate specification track.
- The spec binds to an oracle version: `(weidu-version ...)` names the
  WeiDU build whose dump output this spec describes.  Dump comparison is
  only meaningful against dumps from that build.

A dump file is *valid* iff it parses as an S-expression, its envelope
matches the grammar root declared in `(grammars ...)`, and every node can
be produced from the def catalog by the encoding rules of
`README.md` (File format section).  The spec plus those rules are
complete enough to generate both a dump *emitter* and a dump *reader*.

## File grammar

The file itself is an S-expression in the same concrete syntax as dumps
(double-quoted strings, `;` comments to end of line).  Structure:

```lisp
(ast-spec
  (spec-version N)                    ; format version of this file
  (weidu-version "X")                 ; oracle binding (non-normative)
  (scalars <name> ...)                ; closed scalar universe
  (encodings ...)                     ; atom layer, see below
  (grammars
    (grammar <name> (root <def-name>)) ...)
  (def <def-name> <definition> <attr> ...) ...)
```

- **Header.** `spec-version` governs this file's own format.  The scalar
  universe is closed: `unit bool int int32 string` (as of spec-version 1).
- **Grammars.** Each dump grammar (tp2, tpa, tpp, d, tra, log, baf, bcs,
  ids, refactorbaf) names its root def.  The root of a dump file is the
  node named by that def's wire name.
- **Defs.** One per dumped type.  The catalog is closed-world: every type
  reachable from any root appears exactly once, and every type reference
  resolves to a def name or a scalar.

### Meta-rules

1. **Unknown attributes must be ignored.**  Definitions carry attributes
   beyond their shape (currently `src`, provenance pointing back at the
   WeiDU sources).  Consumers must tolerate and skip any attribute they
   do not implement; new attributes never bump `spec-version`.
2. **`src` is non-normative.**  It exists to link a shape back to the
   code that produced it (original OCaml spelling + location) while that
   code is still around.  A provenance-stripped spec is obtained by
   dropping `src` attributes; nothing else changes.
3. **Def names are global and stable.**  They are the join key between
   this spec, dump files, and diffs.

## The atom layer (nulls)

The `(encodings ...)` header form is the normative statement of how
values render on the wire.  In value position, a dump contains exactly
one of:

```
value ::= quoted-string          ; string values: "..." with \\ \" \n \r \t escapes
        | bare-atom              ; decimal | true | false | none
        | node                   ; (name value...)
```

| scalar | rendering |
|---|---|
| `string` | double-quoted, always — even the empty string and text like `none` |
| `int`, `int32` | bare decimal atom (`-?[0-9]+`) |
| `bool` | bare atom `true` or `false` |
| `unit` | nothing at all (a unit ctor-arg produces no child) |

**Options (nulls).**  A value whose declared type is `(option T)` renders
either as the bare atom `none` (absent) or as a `(some <value>)` node
(present) — never as the unwrapped value.  The bare atom `none` is
**reserved**: no scalar type can produce it (strings are always quoted;
`true`/`false` and decimals are the only other atoms), and no def name or
ctor wire is `none`.  Therefore **absence vs. value is decidable from the
declared type alone**, without inspecting the token: if the type is an
option, `none` means absent; if it is not, `none` cannot occur.

The option inventory as of this spec (all inner shapes, with counts):
`(option string)`, `(option bool)`, `(option tp.tp_patchexp)`,
`(option tp.tp_pe_string)`, `(option dlg.tlk_string)`,
`(option tp.tp_cache_arg)`, `(option (list tp.tp_patch))`,
`(option (tuple tp.tp_patchexp string))`,
`(option (tuple dlg.journal_type dlg.tlk_string))`.  There are no nested
options and no `(option unit)`; an option's present-value type is
therefore never itself ambiguous between atom and node.

Consumers must enforce this layer in both directions: an emitter renders
each value exactly per its declared type's row above; a reader/validator
rejects any value whose lexical form does not match its declared type
(e.g. a bare atom at a `string` position, or `none` at a non-option
position).  The corpus walk described at the end of this document
performs exactly these checks.

## Definitions

Four kinds.  `<texpr>` is a type expression:

```
<texpr> ::= <scalar>                       unit bool int int32 string
          | <def-name>                     reference to another def
          | (option <texpr>)
          | (list <texpr>)
          | (array <texpr>)                source type is an array; emits as (list ...)
          | (tuple <texpr> ...)
```

### `record` — labeled product backed by a source type

```lisp
(def bcs.trigger (record
  (field trigger_id int32)
  (field negated bool)
  ...)
  (src "Bcs.trigger" "src/bcs.ml:26"))
```

- Fields are emitted in **wire order**, which is the order dumps contain
  them.
- Labels are the real component identity of the source type.  A
  reimplementation may address fields however it likes internally, but
  the dump emitter must use these labels, in this order.
- The def name equals the dump node name (`bcs.trigger`).

### `variant` — tagged sum

```lisp
(def tp.tp_flag (variant
  (ctor version (wire "tp_flag.version") (arg dlg.tlk_string))
  (ctor tp_no_if_eval (wire "tp_flag.tp_no_if_eval") (arg unit))
  ...)
  (src "Tp.tp_flag" "src/tp.ml:42"))
```

- **The def name of a variant is a structural key only** — the lowercased
  qualified type name.  It never appears as a dump node; *constructor
  wire names* do.
- **Ctor wire names are literal data, not derivable.**  This is an
  empirical property of the reference output: dump node names for
  constructors come in two-part (`tp_flag.version`), three-part
  (`dc.action.append`, `ids.arg_kind.arg_object`,
  `load.script_style.none`) and — for record defs — even dotless
  (`tp_file`, `store_args`, `local_string_entry`) spellings, with no rule
  that reproduces them.  Consumers must therefore read wire names from
  this file and never synthesize them.
- Constructors are positional: each `(arg ...)` in order.  Zero-arg
  constructors have no `(arg ...)`; a `(arg unit)` constructor dumps as a
  node with no children.
- **Args are wire-args, recorded per constructor.**  A constructor whose
  reference emitter serializes each payload component separately records
  N args, dumped as `(arg-1 ...)` ... `(arg-N ...)` wrappers.  A
  constructor whose payload is emitted as a *single tuple node* — e.g.
  `tp_action.tp_inlined_file`, whose two string components dump as one
  `pair` node — records one `(arg (tuple ...))`.  The distinction is a
  wire convention of the reference implementation (both look identical in
  the source type declaration); it is recorded here as data, never
  derived.  A tuple-typed arg dumps as the `pair`...`oct` node with
  `(arg-i ...)` element wrappers.
- Ctor keys (e.g. `version`) are local to their variant and lowercase;
  the `(src ...)` attribute preserves the original source spelling
  (`Version`, `TP_No_If_Eval`, ...).

### `alias` — synonym rendered as its own node

```lisp
(def bcs.point_param (alias (tuple int32 int32))
  (fields x y))
(def bcs.script (alias (list bcs.condition_response))
  (label list))
```

- Tuple aliases are **positional products**: elements have no labels of
  their own in the source.  The `(fields ...)` labels are wire cosmetics
  invented by the reference dump emitter; a reimplementation should map
  the def to a positional tuple/product and use these labels only when
  emitting dumps.
- List aliases have a single child label (`(label ...)`).
- The def name equals the dump node name.

### `wrapper` — envelope node with no source type

```lisp
(def dc.d_file (wrapper (field list (list dc.action))))
(def tra.entry (wrapper (tuple int dlg.tlk_string))
  (fields str_ref text))
```

Envelopes invented by the dump emitter to name a grammar root
(`dc.d_file`, `tp.tp_action_list`, `tra.tra_file`, `log.log_file`,
`ids.ids_file`, `refactorbaf.trigger_list`) or an anonymous entry shape
(`tra.entry`, `log.entry`).  Shape rules are as for `record` (single
field) or tuple alias (positional + `(fields ...)` cosmetics).

## Labels vs positions (normative summary)

| def kind | wire labels | structural meaning | reimplementation mapping |
|---|---|---|---|
| `record` | real field names | component identity | named fields; internal naming free |
| `alias` (tuple) | invented literals | positional elements | positional product |
| `variant` args | `(arg-N ...)` wrappers (mechanical) | positional | positional args |
| `wrapper` | single field label or `(fields ...)` | as record / tuple alias | as above |

Order is normative **on the wire** for every kind (dumps are
byte-compared).  Internally, consumers are free to address labeled
fields positionally or rename them; only the dump emitter and dump
reader/validator must honor labels and order.

## Bootstrap provenance and verified invariants

`tools/extract_spec.py` seeded this file once from the WeiDU sources by
joining type declarations against the hand-written serializers.  At
bootstrap time the following invariants were verified mechanically and
hold for spec-version 1:

1. **Literal accounting** — every node-name literal in the reference
   serializers appears in the spec (as a def name, ctor wire, or
   format-core node), with none left over.
2. **Label parity** — for every record, the wire label order equals the
   source declaration order (no serializer reordering exists).
3. **Constructor parity** — for every variant, the number of ctor wires
   equals the number of declared constructors.
4. **Closed world** — every type reference resolves to a def name or a
   scalar; 64 defs cover all ten grammars.

A second, independent validation pass (fresh checker, reverse direction:
spec → sources, plus a type-directed walk of real dump output) confirmed
the catalog: every def re-derives from the OCaml declarations and
serializers, and every node in ~180 real dump files resolves through the
spec with exact field, arity, and shape conformance.  The pass also
surfaced the tuple-arg wire convention above, which the first extraction
had missed.

After adoption, changes to AST structure land in this file first;
implementations (including the reference one) are changed to match and
re-validated against dumps of the bound oracle version.
