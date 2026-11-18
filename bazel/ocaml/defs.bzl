"""Minimal OCaml build rules driving the project's hermetic toolchain.

These rules replicate the hand-rolled Makefile.ocaml engine exactly:

  compile:  ocamlopt(.opt) -unsafe-string -w y -ccopt -w -g -I ... -c <mod>.ml
  link:     ocamlopt(.opt) -unsafe-string -w y -ccopt -w -g -o <out>
              <stdlib>/unix.cmxa <stdlib>/str.cmxa
              -cclib -lunix -cclib -lcamlstr [<extra -cclib ...>]
              [<resources.o>] <mod.cmx ...> <stub.o ...>

Action mechanics (chosen so identical rules work on Linux and Windows hosts):

  * Every action runs a generated script through the toolchain's bash.
  * ocamlopt -c, ocamllex, ocamlyacc and elkhound all write their outputs
    next to the input file, so those actions change into the rule's declared
    output directory and stage their inputs there first.
  * Source paths, -I dirs, PATH and OCAMLLIB are made absolute at runtime via
    $ROOT (the execroot) so they keep working under Bazel's action sandboxes.
  * Dependency model: each module receives the interfaces (.cmi) and
    implementations (.cmx) of every earlier module of the binary's canonical
    link order (a conservative superset of ocamldep's answer, since that
    order is topologically sorted). This keeps the rules small; per-module
    caching still applies.
"""

# The toolchain provides platform_common.ToolchainInfo (accessed via
# ctx.toolchains["//bazel/ocaml:toolchain_type"]); no custom provider load.

# Flags copied verbatim from Configuration/Makefile.ocaml (NATIVECAML mode).
_COMPILE_FLAGS = ["-unsafe-string", "-w", "y", "-ccopt", "-w", "-g"]

OcamlModuleInfo = provider(
    doc = "Compiled module artifacts; files is transitively closed over deps.",
    fields = ["name", "files", "cmx"],
)

def _preamble(tc, out_dir):
    """Script header: fix CWD-relative toolchain paths via absolute $ROOT."""
    return "\n".join([
        "set -e",
        "ROOT=$(pwd)",
        'export PATH="$ROOT/{bin}":/usr/local/bin:/usr/bin:/bin'.format(bin = tc.bin_rel),
        'export OCAMLLIB="$ROOT/{lib}"'.format(lib = tc.stdlib_rel),
        'export CAML_LD_LIBRARY_PATH="$ROOT/{lib}/stublibs"'.format(lib = tc.stdlib_rel),
        'mkdir -p "{out}"'.format(out = out_dir),
        'cd "{out}"'.format(out = out_dir),
    ])

def _dep_dirs(dep_files):
    dirs = []
    for f in dep_files:
        if f.dirname not in dirs:
            dirs.append(f.dirname)
    return dirs

def _stage(src_file, out_dir, staged_name, lines):
    """Copies src into the output dir under staged_name unless already there.

    Runs after the script has cd'd into out_dir, so both paths are anchored
    to $ROOT (the execroot) explicitly.
    """
    if src_file.dirname == out_dir and src_file.basename == staged_name:
        return
    d = staged_name[:staged_name.rfind("/")] if "/" in staged_name else ""
    if d:
        lines.append('mkdir -p "$ROOT/{out}/{d}"'.format(out = out_dir, d = d))
    lines.append('cp "$ROOT/{src}" "$ROOT/{out}/{name}"'.format(
        src = src_file.path,
        out = out_dir,
        name = staged_name,
    ))

def _run(ctx, tc, script, inputs, outputs, tools, mnemonic):
    ctx.actions.run(
        inputs = depset(inputs, transitive = [tc.tool_files]),
        outputs = outputs,
        executable = tc.bash,
        arguments = ["-c", script],
        tools = tools,
        env = {},
        mnemonic = mnemonic,
        use_default_shell_env = False,
    )

def _ocaml_module_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    name = ctx.label.name
    src = ctx.file.src
    iface = ctx.file.interface if ctx.attr.interface else None

    dep_files = depset(
        transitive = [dep[OcamlModuleInfo].files for dep in ctx.attr.deps],
    ).to_list()
    dep_incs = " ".join(['-I "$ROOT/%s"' % d for d in _dep_dirs(dep_files)])
    tools = [tc.compiler, tc.ocamllex, tc.ocamlyacc, tc.bash]

    ext = src.extension  # ml / mll / mly / in

    if ext == "mly":
        gen_ml = ctx.actions.declare_file(name + ".ml")
        gen_mli = ctx.actions.declare_file(name + ".mli")
        lines = [_preamble(tc, gen_ml.dirname)]
        _stage(src, gen_ml.dirname, name + ".mly", lines)
        lines.append('"$ROOT/{exe}" "{name}.mly"'.format(exe = tc.ocamlyacc.path, name = name))
        _run(ctx, tc, "\n".join(lines), [src], [gen_ml, gen_mli], tools, "OcamlYacc")
        src, iface, ext = gen_ml, gen_mli, "ml"
    elif ext == "mll":
        gen_ml = ctx.actions.declare_file(name + ".ml")
        lines = [_preamble(tc, gen_ml.dirname)]
        _stage(src, gen_ml.dirname, name + ".mll", lines)
        lines.append('"$ROOT/{exe}" "{name}.mll"'.format(exe = tc.ocamllex.path, name = name))
        _run(ctx, tc, "\n".join(lines), [src], [gen_ml], tools, "OcamlLex")
        src, ext = gen_ml, "ml"

    cmx = ctx.actions.declare_file(name + ".cmx")
    o_file = ctx.actions.declare_file(name + ".o")
    out_dir = cmx.dirname

    if iface:
        cmi = ctx.actions.declare_file(name + ".cmi")
        lines = [_preamble(tc, out_dir)]
        _stage(iface, out_dir, name + ".mli", lines)
        lines.append('"{exe}" {flags} {incs} -c "{name}.mli"'.format(
            exe = "$ROOT/" + tc.compiler.path,
            flags = " ".join(_COMPILE_FLAGS),
            incs = dep_incs,
            name = name,
        ))
        _run(ctx, tc, "\n".join(lines), [iface] + dep_files, [cmi], tools, "OcamlCompileIface")
    else:
        cmi = ctx.actions.declare_file(name + ".cmi")

    lines = [_preamble(tc, out_dir)]
    _stage(src, out_dir, name + ".ml", lines)
    if iface:
        _stage(iface, out_dir, name + ".mli", lines)
    lines.append('"{exe}" {flags} {incs} -c "{name}.ml"'.format(
        exe = "$ROOT/" + tc.compiler.path,
        flags = " ".join(_COMPILE_FLAGS),
        incs = dep_incs + ' -I "$ROOT/%s"' % tc.stdlib_rel + " -I .",
        name = name,
    ))
    impl_outputs = [cmx, o_file] + ([] if iface else [cmi])
    impl_inputs = [src] + dep_files + ([iface, cmi] if iface else [])
    _run(ctx, tc, "\n".join(lines), impl_inputs, impl_outputs, tools, "OcamlCompile")

    return [
        DefaultInfo(files = depset([cmi, cmx, o_file])),
        OcamlModuleInfo(
            name = name,
            files = depset([cmi, cmx, o_file], transitive = [depset(dep_files)]),
            cmx = cmx,
        ),
    ]

ocaml_module = rule(
    implementation = _ocaml_module_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "interface": attr.label(allow_single_file = True),
        "deps": attr.label_list(providers = [[OcamlModuleInfo]]),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def _ocaml_c_module_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    src = ctx.file.src
    # ocamlopt -c <file>.c leaves <file>.o in the CWD (the declared output
    # dir); the object name follows the source basename, not the rule name.
    out = ctx.actions.declare_file(src.basename[:-2] + ".o")

    hdr_files = []
    hdr_dirs = []
    for h in ctx.attr.hdrs:
        for f in h[DefaultInfo].files.to_list():
            hdr_files.append(f)
            if f.dirname not in hdr_dirs:
                hdr_dirs.append(f.dirname)

    lines = [_preamble(tc, out.dirname)]
    lines.append('"$ROOT/{exe}" -verbose {flags} {incs} -c "$ROOT/{src}"'.format(
        exe = tc.compiler.path,
        flags = " ".join(_COMPILE_FLAGS),
        incs = " ".join(['-I "$ROOT/%s"' % d for d in hdr_dirs + [tc.stdlib_rel]]),
        src = src.path,
    ))
    _run(ctx, tc, "\n".join(lines), [src] + hdr_files, [out], [tc.compiler, tc.bash], "OcamlCC")
    return [DefaultInfo(files = depset([out]))]

ocaml_c_module = rule(
    implementation = _ocaml_c_module_impl,
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = True),
        "hdrs": attr.label_list(allow_files = True),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def _ocaml_binary_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    mods = [m[OcamlModuleInfo] for m in ctx.attr.modules]

    all_files = depset(transitive = [m.files for m in mods]).to_list()
    inc_dirs = _dep_dirs(all_files)

    c_o_files = []
    for cm in ctx.attr.c_modules:
        c_o_files.extend(cm[DefaultInfo].files.to_list())
    res_o_files = []
    for r in ctx.attr.resources:
        res_o_files.extend(r[DefaultInfo].files.to_list())

    exe_name = ctx.label.name + (".exe" if tc.os == "windows" else "")
    out = ctx.actions.declare_file(exe_name)

    parts = ['"$ROOT/{exe}" {flags} -o "{out}"'.format(
        exe = tc.compiler.path,
        flags = " ".join(_COMPILE_FLAGS),
        out = out.path,
    )]
    parts.append('"{lib}/unix.cmxa" "{lib}/str.cmxa"'.format(lib = "$ROOT/" + tc.stdlib_rel))
    parts.append("-cclib -lunix -cclib -lcamlstr")
    if ctx.attr.extra_linkopts:
        parts.append(" ".join(ctx.attr.extra_linkopts))
    if res_o_files:
        parts.append(" ".join(['"$ROOT/%s"' % f.path for f in res_o_files]))
    parts.append(" ".join(['"%s"' % m.cmx.path for m in mods]))
    parts.append(" ".join(['"$ROOT/%s"' % f.path for f in c_o_files]))
    parts.append(" ".join(['-I "$ROOT/%s"' % d for d in inc_dirs]))

    lines = [_preamble(tc, ".")]
    lines.append(" ".join(parts))
    _run(ctx, tc, "\n".join(lines), all_files + c_o_files + res_o_files, [out],
         [tc.compiler, tc.bash], "OcamlLink")
    return [DefaultInfo(executable = out, files = depset([out]))]

ocaml_binary = rule(
    implementation = _ocaml_binary_impl,
    executable = True,
    attrs = {
        "modules": attr.label_list(mandatory = True, providers = [[OcamlModuleInfo]]),
        "c_modules": attr.label_list(allow_files = True),
        "resources": attr.label_list(allow_files = True),
        "extra_linkopts": attr.string_list(),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def _ocaml_codegen_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    script = ctx.file.script

    outs = list(ctx.outputs.outs)
    staging_paths = ctx.attr.staging_paths
    if len(outs) != len(staging_paths):
        fail("ocaml_codegen: outs and staging_paths must have the same length")
    out_dir = outs[0].dirname

    lines = [_preamble(tc, out_dir)]
    _stage(script, out_dir, ctx.attr.script_rel, lines)
    stage_files = []
    for t, rel in ctx.attr.stage.items():
        f = t[DefaultInfo].files.to_list()[0]
        stage_files.append(f)
        _stage(f, out_dir, rel, lines)
    copy_files = [t[DefaultInfo].files.to_list()[0] for t in ctx.attr.copy.keys()]
    lines.append('"$ROOT/{ocaml}" str.cma unix.cma {opts} "{script}" {args}'.format(
        ocaml = tc.ocaml.path,
        opts = " ".join(ctx.attr.interpreter_opts),
        script = ctx.attr.script_rel,
        args = " ".join(ctx.attr.args),
    ))
    for t, copy_dst in ctx.attr.copy.items():
        f = t[DefaultInfo].files.to_list()[0]
        lines.append('cp "$ROOT/{s}" "{d}"'.format(s = f.path, d = copy_dst))
    for staging, out in zip(staging_paths, outs):
        if staging != out.basename:
            lines.append('mv "{src}" "{dst}"'.format(src = staging, dst = out.basename))

    _run(ctx, tc, "\n".join(lines), [script] + stage_files + copy_files, outs,
         [tc.ocaml, tc.bash], "OcamlCodegen")
    return [DefaultInfo(files = depset(outs))]

ocaml_codegen = rule(
    implementation = _ocaml_codegen_impl,
    attrs = {
        "script": attr.label(mandatory = True, allow_single_file = True),
        "script_rel": attr.string(mandatory = True),
        "stage": attr.label_keyed_string_dict(allow_files = True),
        "args": attr.string_list(),
        "copy": attr.label_keyed_string_dict(allow_files = True),
        "outs": attr.output_list(mandatory = True),
        "staging_paths": attr.string_list(mandatory = True),
        "interpreter_opts": attr.string_list(default = ["-w", "p"]),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def _ocaml_elkhound_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    gr = ctx.file.gr
    gen_ml, gen_mli = ctx.outputs.outs[0], ctx.outputs.outs[1]

    lines = [_preamble(tc, gen_ml.dirname)]
    _stage(gr, gen_ml.dirname, gr.basename, lines)
    lines.append('"$ROOT/{exe}" -ocaml "{gr}"'.format(exe = tc.elkhound.path, gr = gr.basename))
    _run(ctx, tc, "\n".join(lines), [gr], [gen_ml, gen_mli],
         [tc.elkhound, tc.bash], "ElkhoundGenerate")
    return [DefaultInfo(files = depset([gen_ml, gen_mli]))]

ocaml_elkhound = rule(
    implementation = _ocaml_elkhound_impl,
    attrs = {
        "gr": attr.label(mandatory = True, allow_single_file = True),
        "outs": attr.output_list(mandatory = True),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def _ocaml_write_impl(ctx):
    ctx.actions.write(output = ctx.outputs.out, content = ctx.attr.content)
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

ocaml_write = rule(
    implementation = _ocaml_write_impl,
    attrs = {
        "content": attr.string(mandatory = True),
        "out": attr.output(mandatory = True),
    },
)

def _ocaml_windres_impl(ctx):
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    if not tc.windres:
        fail("ocaml_windres requires the Windows toolchain (windres)")
    rc = ctx.file.rc
    version_ml = ctx.file.version
    out = ctx.actions.declare_file(ctx.attr.out)

    lines = [_preamble(tc, out.dirname)]
    lines.append('cp "$ROOT/{rc}" weidu_resources.rc'.format(rc = rc.path))
    lines.append('V=$(grep -m1 \'version =\' "$ROOT/{v}" | cut -d\'"\' -f2)'.format(v = version_ml.path))
    lines.append('MAJOR="${{V:0:3}}"')
    lines.append('MINOR="${{V:3}}"')
    lines.append(" ".join([
        "sed -i",
        '-e "s/FILEVERSION\\W\\+[[:digit:]]\\+,[[:digit:]]\\+,[[:digit:]]\\+,[[:digit:]]\\+/FILEVERSION\\t\\t$MAJOR,$MINOR,0,0/gI"',
        '-e "s/\\"FileVersion\\",\\ \\"[[:digit:]]\\+.[[:digit:]]\\+\\"/\\"FileVersion\\",\\ \\"$MAJOR.$MINOR\\"/gI"',
        '-e "s/\\"ProductVersion\\",\\ \\"[[:digit:]]\\+.[[:digit:]]\\+\\"/\\"ProductVersion\\",\\ \\"$MAJOR.$MINOR\\"/gI"',
        "weidu_resources.rc",
    ]))
    lines.append('"$ROOT/{windres}" -i weidu_resources.rc -o "{out}"'.format(
        windres = tc.windres.path,
        out = out.basename,
    ))
    _run(ctx, tc, "\n".join(lines), [rc, version_ml], [out],
         [tc.windres, tc.bash], "WindresCompile")
    return [DefaultInfo(files = depset([out]))]

ocaml_windres = rule(
    implementation = _ocaml_windres_impl,
    attrs = {
        "rc": attr.label(mandatory = True, allow_single_file = True),
        "version": attr.label(mandatory = True, allow_single_file = True),
        "out": attr.string(mandatory = True),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)

def ocaml_module_chain(modules):
    """Declares an ordered chain of ocaml_module targets (one per entry).

    modules: list of dicts with keys "name", "src" and optional "interface".
    Each module depends on every module declared before it (link-order
    over-approximation of ocamldep, see defs.bzl docstring).
    """
    prev = []
    for m in modules:
        ocaml_module(
            name = m["name"],
            src = m["src"],
            interface = m.get("interface"),
            deps = prev,
        )
        prev.append(":" + m["name"])

def _ocaml_sanity_check_impl(ctx):
    """Runs the built binary through a no-game parse/compile/decompile loop.

    Replicates the manual no-game workflow documented by the upstream fixture
    (test/no-game/make-foozle.d):

      1. --version reports an augmented build.
      2. --nogame compile of a minimal D file produces a DLG V1.0 file and a
         synthesized TLK (" -- NO DIALOG.TLK -- ").
      3. --nogame --text decompiles the DLG back to D containing the original
         strings (D -> DLG -> D round trip through both parsers).
      4. a known-bad D file is rejected with FATAL ERROR (WeiDU exits 0 even
         on parse errors, so the diagnostic output is what is asserted).

    Runs at build time (cached like any action) so `bazel build //...`
    validates the binary on every full build, on every host platform.
    """
    tc = ctx.toolchains["//bazel/ocaml:toolchain_type"]
    binary = ctx.executable.binary
    out = ctx.actions.declare_file(ctx.label.name + ".ok")

    stage_files = []
    for t, _ in ctx.attr.stage.items():
        stage_files.append(t[DefaultInfo].files.to_list()[0])

    lines = [_preamble(tc, out.dirname)]
    lines.append("mkdir -p run")
    lines.append('cd run')
    lines.append('"$ROOT/{bin}" --version > version.txt 2>&1'.format(bin = binary.path))
    lines.append('grep -q -- "WeiDU version" version.txt')
    lines.append('grep -q -- "-augmented" version.txt')
    for t, rel in ctx.attr.stage.items():
        f = t[DefaultInfo].files.to_list()[0]
        lines.append('cp "$ROOT/{s}" "{d}"'.format(s = f.path, d = rel))
    lines.append('"$ROOT/{bin}" --nogame "{good}" > compile.txt 2>&1'.format(bin = binary.path, good = ctx.attr.good_file))
    lines.append('test -s FOOZLE.dlg')
    lines.append('head -c 8 FOOZLE.dlg | grep -q -- "DLG V1.0"')
    lines.append('test -s " -- NO DIALOG.TLK -- "')
    lines.append('"$ROOT/{bin}" --nogame --text FOOZLE.dlg > decompile.txt 2>&1'.format(bin = binary.path))
    lines.append('test -s FOOZLE.d')
    lines.append('grep -q -- "{magic}" FOOZLE.d'.format(magic = ctx.attr.roundtrip_expect))
    # WeiDU exits 0 even on parse errors (top-level handler prints FATAL
    # ERROR), so the diagnostic output is the assertion, not the exit code.
    lines.append('"$ROOT/{bin}" --nogame "{bad}" > bad.txt 2>&1 || true'.format(bin = binary.path, bad = ctx.attr.bad_file))
    lines.append('grep -q -- "FATAL ERROR" bad.txt')
    lines.append('echo ok > "$ROOT/{out}"'.format(out = out.path))

    _run(ctx, tc, "\n".join(lines), [binary] + stage_files, [out],
         [tc.bash], "OcamlSanityCheck")
    return [DefaultInfo(files = depset([out]))]

ocaml_sanity_check = rule(
    implementation = _ocaml_sanity_check_impl,
    attrs = {
        "binary": attr.label(mandatory = True, executable = True, cfg = "exec"),
        # fixture files staged into the scratch run dir
        "stage": attr.label_keyed_string_dict(allow_files = True),
        # staged names of the good and bad D inputs
        "good_file": attr.string(mandatory = True),
        "bad_file": attr.string(mandatory = True),
        # string that must survive the D -> DLG -> D round trip
        "roundtrip_expect": attr.string(mandatory = True),
    },
    toolchains = ["//bazel/ocaml:toolchain_type"],
)
