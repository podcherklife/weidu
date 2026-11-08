#!/usr/bin/env python3
"""Bootstrap extractor: OCaml type declarations + hand-written serializers
-> doc/trace/ast/ast-spec.sexp

This is a BOOTSTRAP tool for the ast-spec workflow (see ../spec-format.md).
It reads the WeiDU sources to seed the spec once; after adoption the spec
file is the source of truth and this tool is expected to be dropped with
the codebase.  It is deliberately conservative: every mismatch it finds is
reported, never silently guessed.

Usage: python3 extract_spec.py  (from the repository root)
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]  # repository root (weidu/)
OUT = ROOT / "doc/trace/ast/ast-spec.sexp"

# OCaml module -> file.  Wire prefixes are always read from the serializers
# as literals, never derived from module names.
MODULES = [
    ("Tp", "src/tp.ml"),
    ("Bcs", "src/bcs.ml"),
    ("Dlg", "src/dlg.ml"),
    ("Dc", "src/dc.ml"),
    ("Ids", "src/ids.ml"),
    ("Util", "src/util.ml"),
    ("Load", "src/load.ml"),
    ("Refactorbaf", "src/refactorbaf.ml"),
]

SERIALIZERS = ["src/astdumpTp.ml", "src/astdumpBcs.ml", "src/astdumpDlg.ml"]

SCALARS = {
    "unit": "unit", "int": "int", "bool": "bool", "string": "string",
    "char": "char", "float": "float",
    "Int32.t": "int32", "Int64.t": "int64",
}

# Grammar roots: (grammar, serializer root function)
ROOTS = [
    ("tp2", "tp_file"),
    ("tpa", "tp_action_list"),
    ("tpp", "tp_patch_list"),
    ("d", "d_file"),
    ("tra", "tra_file"),
    ("log", "log_file"),
    ("baf", "script"),
    ("bcs", "script"),
    ("ids", "ids_file"),
    ("refactorbaf", "refactorbaf_trigger_list"),
]

problems = []
def warn(msg):
    problems.append(msg)
    print("WARN: " + msg)

# ---------------------------------------------------------------- comments

def strip_comments(text):
    """Remove (* ... *) comments (nested), preserving newlines/positions."""
    out = []
    i, n = 0, len(text)
    depth = 0
    while i < n:
        if depth == 0 and text.startswith("(*", i):
            depth = 1; i += 2; out.append("  "); continue
        if depth > 0:
            if text.startswith("(*", i):
                depth += 1; i += 2; out.append("  "); continue
            if text.startswith("*)", i):
                depth -= 1; i += 2; out.append("  "); continue
            out.append(text[i] if text[i] == "\n" else " ")
            i += 1
            continue
        if text.startswith('"', i):
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2; continue
                if text[j] == '"':
                    j += 1; break
                j += 1
            out.append(text[i:j]); i = j; continue
        out.append(text[i]); i += 1
    return "".join(out)

# ------------------------------------------------------- type expressions

TOKEN = re.compile(r"\s*([A-Za-z_][\w'.]*|\*|\(|\))")

def tokenize(s, src="?"):
    toks, i = [], 0
    while i < len(s):
        m = TOKEN.match(s, i)
        if not m:
            if s[i].isspace():
                i += 1; continue
            raise ValueError(f"cannot tokenize at {s[i:]!r} in {s!r} ({src})")
        toks.append(m.group(1)); i = m.end()
    return toks

class T:
    def __init__(self, kind, *kids):
        self.kind, self.kids = kind, kids
    def __eq__(self, other):
        return isinstance(other, T) and self.kind == other.kind and self.kids == other.kids
    def __repr__(self):
        return f"T({self.kind},{self.kids})"

class TypeParser:
    def __init__(self, toks, src):
        self.toks, self.i, self.src = toks, 0, src
    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None
    def next(self):
        t = self.peek(); self.i += 1; return t
    def parse(self):
        t = self.prod()
        if self.peek() is not None:
            raise ValueError(f"trailing tokens {self.toks[self.i:]} in {self.src!r}")
        return t
    def prod(self):
        items = [self.app()]
        while self.peek() == "*":
            self.next(); items.append(self.app())
        return items[0] if len(items) == 1 else T("tuple", *items)
    def app(self):
        t = self.atom()
        while self.peek() in ("list", "option", "array"):
            t = T(self.next(), t)
        return t
    def atom(self):
        tok = self.next()
        if tok == "(":
            t = self.prod()
            if self.next() != ")":
                raise ValueError(f"unbalanced parens in {self.src!r}")
            return t
        if tok is None:
            raise ValueError(f"unexpected EOF in {self.src!r}")
        if tok in SCALARS:
            return T(SCALARS[tok])
        if re.fullmatch(r"[A-Za-z_][\w'.]*", tok):
            return T("ref", tok)
        raise ValueError(f"unexpected token {tok!r} in {self.src!r}")

def parse_texpr(s, src="?"):
    return TypeParser(tokenize(s, src), src).parse()

def t_names(t, acc):
    if t.kind == "ref":
        acc.add(t.kids[0])
    for k in t.kids:
        if isinstance(k, T):
            t_names(k, acc)
    return acc

REF_REWRITE = {}

def t_to_sexp(t):
    if t.kind == "ref":
        return REF_REWRITE.get(t.kids[0], t.kids[0].lower())
    if t.kind in ("list", "option", "array"):
        return f"({t.kind} {t_to_sexp(t.kids[0])})"
    if t.kind == "tuple":
        return "(tuple " + " ".join(t_to_sexp(k) for k in t.kids) + ")"
    return t.kind  # scalar

# ------------------------------------------------------ type declarations

class Decl:
    def __init__(self, mod, name, kind, line, file):
        self.mod, self.name, self.kind, self.line, self.file = mod, name, kind, line, file
        self.fields_raw = []  # record: (label, raw type text)
        self.ctors_raw = []   # variant: (CtorName, raw payload|None, line)
        self.alias_raw = None
        self._lazy = {}
    @property
    def qname(self):
        return f"{self.mod}.{self.name}"
    def fields(self, decls):
        if "fields" not in self._lazy:
            self._lazy["fields"] = [
                (label, qualify(parse_texpr(raw, f"{self.file}:{self.line} {label}"),
                                self.mod, decls))
                for label, raw in self.fields_raw]
        return self._lazy["fields"]
    def ctors(self, decls):
        if "ctors" not in self._lazy:
            out = []
            for cname, raw, line in self.ctors_raw:
                if raw is None:
                    out.append((cname, []))
                else:
                    t = qualify(parse_texpr(raw, f"{self.file}:{line} {cname}"),
                                self.mod, decls)
                    out.append((cname, list(t.kids) if t.kind == "tuple" else [t]))
            self._lazy["ctors"] = out
        return self._lazy["ctors"]
    def alias(self, decls):
        if "alias" not in self._lazy:
            self._lazy["alias"] = qualify(
                parse_texpr(self.alias_raw, f"{self.file}:{self.line}"),
                self.mod, decls)
        return self._lazy["alias"]

def parse_declarations():
    decls = {}
    order = []
    for mod, path in MODULES:
        text = strip_comments((ROOT / path).read_text())
        lines = text.split("\n")
        starts = []
        for idx, ln in enumerate(lines):
            m = re.match(r"^(type|and)\s+(\w+)\s*=", ln)
            if m:
                starts.append((idx, m.group(2)))
        for k, (idx, name) in enumerate(starts):
            end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
            for j in range(idx + 1, end):
                if re.match(r"^(let|exception|open|module)\b|^;;", lines[j]):
                    end = j; break
            body = "\n".join(lines[idx:end])
            line_no = idx + 1
            d = Decl(mod, name, None, line_no, path)
            b = body[body.index("=") + 1:].replace(";;", " ")
            if re.match(r"\s*\{", b):
                d.kind = "record"
                inner = b[b.index("{") + 1: b.rindex("}")]
                for part in inner.split(";"):
                    part = part.strip()
                    if not part:
                        continue
                    m = re.match(r"(mutable\s+)?(\w+)\s*:\s*(.+)$", part, re.S)
                    if not m:
                        warn(f"{path}:{line_no} record {name}: unparsable field {part[:60]!r}")
                        continue
                    d.fields_raw.append((m.group(2), " ".join(m.group(3).split())))
            elif re.search(r"(?m)^\s*\|", b) or re.fullmatch(
                    r"\s*[A-Z]\w*(\s*\|\s*[A-Z]\w*)*\s*", b):
                d.kind = "variant"
                ctors, buf, depth, i = [], [], 0, 0
                in_str = False
                while i < len(b):
                    c = b[i]
                    if in_str:
                        buf.append(c)
                        if c == "\\":
                            buf.append(b[i+1]); i += 2; continue
                        if c == '"': in_str = False
                        i += 1; continue
                    if c == '"': in_str = True; buf.append(c); i += 1; continue
                    if c in "([": depth += 1
                    elif c in ")]": depth -= 1
                    elif c == "|" and depth == 0:
                        ctors.append("".join(buf)); buf = []; i += 1; continue
                    buf.append(c); i += 1
                ctors.append("".join(buf))
                for ctext in ctors:
                    ctext = " ".join(ctext.split())
                    ctext = ctext.replace(";;", " ").strip()
                    if not ctext:
                        continue
                    m = re.match(r"([A-Z]\w*)\s*(?:of\s+(.+))?$", ctext, re.S)
                    if not m:
                        warn(f"{path}:{line_no} variant {name}: unparsable ctor {ctext[:60]!r}")
                        continue
                    d.ctors_raw.append((m.group(1), m.group(2), line_no))
            else:
                d.kind = "alias"
                d.alias_raw = " ".join(b.split()).replace(";;", " ").strip()
            key = f"{mod}.{name}"
            if key in decls:
                warn(f"duplicate declaration {key}")
            decls[key] = d
            order.append(key)
    return decls, order

def resolve_ref(name, decls, ctx_mod=None):
    """Bare or qualified type name -> decl key.  Bare names prefer the
    declaration's own module (OCaml resolution within the module)."""
    if "." in name:
        return name if name in decls else None
    if ctx_mod and f"{ctx_mod}.{name}" in decls:
        return f"{ctx_mod}.{name}"
    hits = [k for k in decls if k.split(".", 1)[1] == name]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        warn(f"ambiguous bare type name {name!r}: {hits}")
    return None

def qualify(t, ctx_mod, decls):
    """Rewrite bare refs to qualified decl keys (module-context aware)."""
    if t.kind == "ref":
        key = resolve_ref(t.kids[0], decls, ctx_mod)
        if key is None:
            return t
        return T("ref", key)
    return T(t.kind, *[qualify(k, ctx_mod, decls) if isinstance(k, T) else k
                       for k in t.kids])

# ---------------------------------------------------------- serializer pass

class SFun:
    def __init__(self, name, line, file):
        self.name, self.line, self.file = name, line, file
        self.ann = None       # T or None
        self.wire = None      # first node_start literal
        self.fields = []      # (label, fkind, fnname_or_None) in order
        self.ctors = {}       # CtorName -> wire
        self.ctor_bodies = {} # CtorName -> branch source text
        self.lambdas = []     # (wire, arity, [labels])

def parse_serializers():
    funs = {}             # (file, fname) -> SFun
    for path in SERIALIZERS:
        lines = (ROOT / path).read_text().split("\n")
        starts = []
        for idx, ln in enumerate(lines):
            m = re.match(r"^(?:let rec |let |and )([a-z_][\w']*)\s", ln)
            if m:
                starts.append((idx, m.group(1)))
        for k, (idx, fname) in enumerate(starts):
            end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
            body = "\n".join(lines[idx:end])
            f = SFun(fname, idx + 1, path)
            # annotation: last ':' in the header (up to first '='); the type
            # runs from after ':' to the ')' that closes the param group.
            header = body[:body.find("=")]
            cpos = header.rfind(":")
            if cpos >= 0:
                depth, j = 0, cpos + 1
                while j < len(body):
                    c = body[j]
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        if depth == 0:
                            break
                        depth -= 1
                    j += 1
                annsrc = " ".join(body[cpos + 1:j].split())
                if "->" not in annsrc and annsrc:
                    try:
                        f.ann = parse_texpr(annsrc, f"{path}:{idx+1}")
                    except ValueError as e:
                        warn(f"annotation parse {f.name}: {e}")
            m = re.search(r'node_start o "([^"]+)"', body)
            if m:
                f.wire = m.group(1)
            body_nolambda = re.sub(
                r"\(\s*fun\s+o\s*\([^)]*\)\s*->.*?node_end o\)", " LAMBDA ",
                body, flags=re.S)
            for fm in re.finditer(
                    r'f_(str|int|i32|bool|atom|node|opt|list|array)\s+o\s+"([^"]+)"\s+([a-z_][\w\']*)?',
                    body_nolambda):
                f.fields.append((fm.group(2), fm.group(1), fm.group(3)))
            wpos = body.find("match")
            if wpos >= 0 and "with" in body[wpos:wpos + 200]:
                mbody = body[wpos:]
                parts = re.split(r"(?m)^\s*\|\s*", mbody)
                for part in parts[1:]:
                    cm = re.match(r"(?:[A-Z]\w*\.)?([A-Z]\w*)", part)
                    wm = re.search(r'node_start o "([^"]+)"', part)
                    if cm and wm:
                        f.ctors[cm.group(1)] = wm.group(1)
                        f.ctor_bodies[cm.group(1)] = part
            for lm in re.finditer(r"\(\s*fun\s+o\s*\(([^)]*)\)\s*->", body):
                arity = len(lm.group(1).split(","))
                nend = body.find("node_end o)", lm.start())
                seg = body[lm.start():nend] if nend >= 0 else body[lm.start():lm.start() + 800]
                wm = re.search(r'node_start o "([^"]+)"', seg)
                labels = re.findall(
                    r'f_(?:str|int|i32|bool|atom|node|opt)\s+o\s+"([^"]+)"', seg)
                if wm:
                    f.lambdas.append((wm.group(1), arity, labels))
            funs[(path, fname)] = f
    return funs

def lookup_fun(funs, fname, prefer_path=None):
    if prefer_path and (prefer_path, fname) in funs:
        return funs[(prefer_path, fname)]
    hits = [f for (_p, n), f in funs.items() if n == fname]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        warn(f"ambiguous serializer function {fname!r}")
    return None

# --------------------------------------------------------------- assembly

def main():
    decls, order = parse_declarations()
    funs = parse_serializers()

    # classify serializer functions:
    #  - annotation is a qualified ref              -> serializer for that type
    #  - annotation shape matches a declared alias  -> serializer for the alias
    #  - otherwise (list/tuple expr, own wire)      -> wrapper node
    alias_by_shape = {}
    for key in decls:
        d = decls[key]
        if d.kind == "alias":
            try:
                alias_by_shape[t_to_sexp(d.alias(decls))] = key
            except ValueError as e:
                warn(f"alias parse {key}: {e}")

    type_fun = {}     # decl key -> SFun
    wrappers = []     # SFun
    for (_path, _fname), f in funs.items():
        if f.ann is None or f.wire is None:
            continue
        if f.ann.kind == "ref":
            key = f.ann.kids[0]
            if key not in decls:
                resolved = resolve_ref(key, decls)
                if resolved is None:
                    warn(f"serializer {f.file}:{f.name}: type {key!r} not declared")
                    continue
                key = resolved
            if key in type_fun:
                warn(f"two serializers for {key}: {type_fun[key].name}, {f.name}")
            type_fun[key] = f
            continue
        if False:
            key = None
            if key in type_fun:
                warn(f"two serializers for {key}: {type_fun[key].name}, {f.name}")
            type_fun[key] = f
        else:
            shape = t_to_sexp(f.ann)
            if shape in alias_by_shape:
                key = alias_by_shape[shape]
                if key in type_fun:
                    warn(f"two serializers for alias {key}: "
                         f"{type_fun[key].name}, {f.name}")
                type_fun[key] = f
            else:
                wrappers.append(f)

    root_funs = {}
    for gname, fname in ROOTS:
        f = lookup_fun(funs, fname)
        if f is None:
            warn(f"root function {fname} not found")
            continue
        root_funs[gname] = f

    wire_by_key = {key: f.wire for key, f in type_fun.items()}

    # reachability from roots over declarations
    dumped = set()
    work = []
    for gname, f in root_funs.items():
        if f.ann is None:
            warn(f"root {gname} ({f.name}) has no annotation")
            continue
        for n in t_names(f.ann, set()):
            key = resolve_ref(n, decls)
            if key:
                work.append(key)
    while work:
        key = work.pop()
        if key in dumped or key not in decls:
            continue
        dumped.add(key)
        d = decls[key]
        refs = set()
        try:
            if d.kind == "record":
                for _fl, t in d.fields(decls):
                    refs |= t_names(t, set())
            elif d.kind == "variant":
                for _cname, args in d.ctors(decls):
                    for t in args:
                        refs |= t_names(t, set())
            elif d.kind == "alias":
                refs |= t_names(d.alias(decls), set())
        except ValueError as e:
            warn(f"reachability {key}: {e}")
            continue
        for n in refs:
            key2 = resolve_ref(n, decls, d.mod)
            if key2:
                work.append(key2)

    # aliases serialized inline via lambdas (e.g. bcs.rect_param)
    for key in dumped:
        if key in wire_by_key or decls[key].kind != "alias":
            continue
        at = decls[key].alias(decls)
        arity = len(at.kids) if at.kind == "tuple" else 1
        cands = []
        for f in funs.values():
            for (wire, larity, labels) in f.lambdas:
                if larity == arity and decls[key].name.lower() in wire.lower():
                    cands.append((wire, labels))
        if len(cands) == 1:
            wire_by_key[key] = cands[0][0]
        else:
            warn(f"alias {key}: no unique inline serializer ({len(cands)} candidates)")

    for k in sorted(dumped):
        if k not in wire_by_key:
            warn(f"no wire name for {k}")

    # refs render as the referenced def's name
    for key in dumped:
        d = decls[key]
        REF_REWRITE[key] = (key.lower() if d.kind == "variant"
                            else wire_by_key.get(key, key.lower()))

    # entry wrappers: tuple-annotated wrappers used as list elements
    entry_by_shape = {t_to_sexp(f.ann): f for f in wrappers if f.ann.kind == "tuple"}

    def subst_entry(t):
        """Inside wrapper field types, replace element tuples that have a
        dedicated entry wrapper (tra.entry, log.entry) with its wire ref."""
        if t.kind == "list" and t.kids[0].kind == "tuple":
            shape = t_to_sexp(t.kids[0])
            if shape in entry_by_shape:
                return T("list", T("ref", entry_by_shape[shape].wire))
        return t

    # ------------------------------------------------------------- emit
    lines = []
    emit = lines.append
    emit("(ast-spec")
    emit("  (spec-version 1)")
    emit('  (weidu-version "25201")')
    emit(f"  ; bootstrap-extracted from the WeiDU sources by"
         f" doc/trace/ast/tools/extract_spec.py; {len(dumped)} defs.")
    emit("  ; See spec-format.md for the format contract.  Consumers must")
    emit("  ; ignore attributes they do not know (e.g. src).")
    emit("  (scalars unit bool int int32 string)")
    emit("  (encodings")
    emit("    ; how each scalar renders on the wire (see spec-format.md)")
    emit("    (scalar string quoted)            ; double-quoted, escaped")
    emit("    (scalar int (atom decimal))       ; bare atom")
    emit("    (scalar int32 (atom decimal))     ; bare atom")
    emit("    (scalar bool (atom true false))   ; bare atoms")
    emit("    (scalar unit empty)               ; renders as nothing")
    emit("    ; absent option renders as the bare atom `none`; present as")
    emit("    ; a (some <value>) node.  `none` is reserved: no scalar")
    emit("    ; type can produce it, so absence is decidable from the")
    emit("    ; declared type alone.")
    emit("    (option (absent none) (present some))")
    emit("  )")
    emit("")
    emit("  (grammars")
    for gname, _fname in ROOTS:
        f = root_funs.get(gname)
        if f is None:
            continue
        emit(f'    (grammar {gname} (root {f.wire}))')
    emit("  )")
    emit("")

    emitted = set()

    def emit_def(key):
        if key in emitted or key not in dumped or key not in wire_by_key:
            return
        emitted.add(key)
        d = decls[key]
        w = wire_by_key[key]
        if d.kind == "variant":
            w = key.lower()   # structural key; ctor wires carry the dump names
        src = f'(src "{d.qname}" "{d.file}:{d.line}")'
        try:
            if d.kind == "record":
                sf = type_fun.get(key)
                if sf is None:
                    warn(f"record {key} has no serializer function")
                    return
                labels = [l for l, _k, _f in sf.fields]
                decl_labels = [fl for fl, _ in d.fields(decls)]
                if labels != decl_labels:
                    warn(f"record {key}: serializer label order {labels} != "
                         f"declaration order {decl_labels}")
                emit(f"  (def {w} (record")
                for fl, t in d.fields(decls):
                    emit(f"    (field {fl} {t_to_sexp(t)})")
                emit("  )")
                emit(f"    {src})")
            elif d.kind == "variant":
                sf = type_fun.get(key)
                if sf is None:
                    warn(f"variant {key} has no serializer function")
                    return
                emit(f"  (def {w} (variant")
                for cname, args in d.ctors(decls):
                    cw = sf.ctors.get(cname)
                    if cw is None:
                        warn(f"variant {key}: ctor {cname} has no wire in serializer")
                        cw = f"??{cname}"
                    body = sf.ctor_bodies.get(cname, "")
                    # tuple-node style: the ctor payload is serialized by a
                    # single pair/... call, never via arg-N wrappers
                    tuple_node = ("arg-1" not in body and bool(re.search(
                        r"\b(pair|triple|quad|quint|sext|sept|oct)\s+[a-z_]",
                        body)))
                    if tuple_node and len(args) > 1:
                        # single tuple argument rendered as a pair/... node
                        args = [T("tuple", *args)]
                    elif tuple_node and len(args) == 1:
                        pass  # already a single arg
                    if tuple_node and len(args) == 1 and \
                            not (args[0].kind == "tuple"):
                        warn(f"variant {key}.{cname}: tuple-node rendering but "
                             f"payload is not a tuple")
                    args_sexp = " ".join(f"(arg {t_to_sexp(t)})" for t in args)
                    csrc = f'(src "{d.mod}.{cname}" "{d.file}")'
                    emit(f'    (ctor {cname.lower()} (wire "{cw}") {args_sexp} {csrc})')
                emit("  )")
                emit(f"    {src})")
            elif d.kind == "alias":
                at = d.alias(decls)
                labels = None
                if key in type_fun:
                    labels = [l for l, _k, _f in type_fun[key].fields]
                else:
                    for f2 in funs.values():
                        for cwire, _ar, clabels in f2.lambdas:
                            if cwire == w:
                                labels = clabels
                                break
                if at.kind == "tuple" and labels:
                    if len(labels) != len(at.kids):
                        warn(f"alias {key}: {len(labels)} labels for "
                             f"{len(at.kids)}-tuple")
                    emit(f"  (def {w} (alias {t_to_sexp(at)})")
                    emit(f"    (fields {' '.join(labels)})")
                    emit(f"    {src})")
                else:
                    emit(f"  (def {w} (alias {t_to_sexp(at)})")
                    if labels:
                        emit(f"    (label {' '.join(labels)})")
                    emit(f"    {src})")
        except ValueError as e:
            warn(f"emit {key}: {e}")

    # wrappers first: grammar roots, then entry wrappers
    for gname, _fname in ROOTS:
        f = root_funs.get(gname)
        if f is None or f not in wrappers:
            continue  # named-type root: emitted with its def below
        t = subst_entry(f.ann)
        labels = [l for l, _k, _f in f.fields]
        if len(labels) != 1:
            warn(f"wrapper {f.name}: expected 1 field, got {labels}")
        emit(f"  (def {f.wire} (wrapper (field {labels[0] if labels else '?'}"
             f" {t_to_sexp(t)}))")
        emit(f'    (src "{f.name}" "{f.file}:{f.line}"))')
    for f in wrappers:
        if f in root_funs.values() or f.ann.kind != "tuple":
            continue
        labels = [l for l, _k, _f in f.fields]
        emit(f"  (def {f.wire} (wrapper {t_to_sexp(f.ann)})")
        emit(f"    (fields {' '.join(labels)})")
        emit(f'    (src "{f.name}" "{f.file}:{f.line}"))')
    emit("")

    modorder = {m: i for i, (m, _p) in enumerate(MODULES)}
    for key in sorted(dumped, key=lambda k: (modorder.get(k.split(".")[0], 99),
                                             decls[k].line)):
        emit_def(key)
    emit(")")

    # closed-world check: every type ref resolves to an emitted def or scalar
    spec_text = "\n".join(lines)
    scalars = {"unit", "bool", "int", "int32", "string"}
    def_names = set()
    for m in re.finditer(r"\(def (\S+) ", spec_text):
        def_names.add(m.group(1))
    bad_refs = set()
    for key in dumped:
        d = decls[key]
        try:
            ts = []
            if d.kind == "record":
                ts = [t for _f, t in d.fields(decls)]
            elif d.kind == "variant":
                ts = [t for _c, args in d.ctors(decls) for t in args]
            elif d.kind == "alias":
                ts = [d.alias(decls)]
            for t in ts:
                for n in t_names(t, set()):
                    nn = REF_REWRITE.get(n, n.lower())
                    if nn not in def_names | scalars:
                        bad_refs.add(n)
        except ValueError:
            pass
    if bad_refs:
        warn(f"unresolved type refs in spec: {sorted(bad_refs)}")

    # ctor-count parity: parser-extracted branches vs declared ctors
    for key in dumped:
        d = decls[key]
        sf = type_fun.get(key)
        if d.kind == "variant" and sf is not None:
            if len(sf.ctors) != len(d.ctors(decls)):
                warn(f"variant {key}: serializer has {len(sf.ctors)} ctor wires "
                     f"but type declares {len(d.ctors(decls))}")

    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT} ({len(dumped)} defs, {len(problems)} warnings)")

    # ---------------------------------------------------------- validation
    spec_text = "\n".join(lines)
    ctor_wires = set(re.findall(r'\(wire "([^"]+)"\)', spec_text))
    spec_wires = (set(wire_by_key.values()) | {f.wire for f in wrappers}
                  | ctor_wires)
    used = set()
    for path in SERIALIZERS:
        used |= set(re.findall(r'node_start o "([^"]+)"',
                               (ROOT / path).read_text()))
    unaccounted = used - spec_wires
    if unaccounted:
        print(f"UNACCOUNTED node_start literals ({len(unaccounted)}): "
              f"{sorted(unaccounted)}")
    else:
        print("all serializer node literals accounted for in the spec")

    undumped = [k for k in order if k not in dumped]
    print(f"declared-but-undumped ({len(undumped)}): {undumped}")

if __name__ == "__main__":
    sys.exit(main())
