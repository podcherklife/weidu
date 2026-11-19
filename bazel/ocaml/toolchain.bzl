"""OCaml toolchain rule for weidu-augmented.

The toolchain is produced/fetched by repository rules (see repos.bzl) and
exposed here as a uniform set of executable files plus the paths needed to
run them correctly inside Bazel action sandboxes:

  * OCAMLLIB/CAML_LD_LIBRARY_PATH and PATH are exported *inside* each action
    script (see defs.bzl) as $ROOT-anchored absolute paths, so they work in
    sandboxed and unsandboxed executions alike (the compiler's embedded
    stdlib path is absolute and would otherwise break under sandboxing).
  * action_path/bin_rel let the action scripts prepend the toolchain bin dir
    so ocamlopt finds its configured C compiler (cc-wrapper.sh on Linux,
    gcc.exe on Windows) and shell utilities come from the toolchain prefix
    on Windows.
"""

def _ocaml_toolchain_impl(ctx):
    # Derive the execroot-relative toolchain paths from the compiler file so
    # they stay correct under bzlmod's repo-mapped external/ layout
    # (external/+<extension>+<repo>/...) on any Bazel version.
    bin_dir = ctx.file.compiler.dirname
    stdlib_dir = bin_dir + "/../lib/ocaml"
    return [platform_common.ToolchainInfo(
        compiler = ctx.file.compiler,      # ocamlopt(.opt) executable
        ocaml = ctx.file.ocaml,            # bytecode interpreter (codegen)
        ocamllex = ctx.file.ocamllex,
        ocamlyacc = ctx.file.ocamlyacc,
        elkhound = ctx.file.elkhound,      # host-side parser generator
        bash = ctx.file.bash,              # bash for action scripts
        windres = ctx.file.windres if ctx.attr.windres else None,
        tool_files = ctx.attr.tool_files[DefaultInfo].files,
        stdlib_rel = stdlib_dir,           # execroot-relative stdlib dir
        bin_rel = bin_dir,                 # execroot-relative compiler bin dir
        os = ctx.attr.os,                  # "linux"
        action_path = bin_dir,
    )]

ocaml_toolchain = rule(
    implementation = _ocaml_toolchain_impl,
    attrs = {
        "compiler": attr.label(mandatory = True, allow_single_file = True),
        "ocaml": attr.label(mandatory = True, allow_single_file = True),
        "ocamllex": attr.label(mandatory = True, allow_single_file = True),
        "ocamlyacc": attr.label(mandatory = True, allow_single_file = True),
        "elkhound": attr.label(mandatory = True, allow_single_file = True),
        "bash": attr.label(mandatory = True, allow_single_file = True),
        "windres": attr.label(allow_single_file = True),
        "tool_files": attr.label(mandatory = True),
        # Informational; windows targets go through the container
        # cross-build, which does not use a toolchain at all.
        "os": attr.string(mandatory = True, values = ["linux"]),
    },
)
