"""Repository rules providing the OCaml toolchains and the elkhound generator.

Supply-chain contract (see bazel/README.md): every artifact fetched here comes
from a public upstream that the project already trusts:

  * OCaml compiler source: github.com/ocaml/ocaml (hash independently
    recorded by opam-repository for ocaml-base-compiler.4.08.1).
  * elkhound binaries: The-Mod-Elephant/elkhound release 1.0.3, the same
    assets referenced by .github/workflows/main.yaml.
  * Windows toolchain: prebuilt MSYS2 archive packages from repo.msys2.org.

Nothing is hosted by this repository, and no container runtime is required
for the Bazel build.

On Linux the OCaml compiler is built from source on the host (gcc + make +
bash required), which keeps the produced compiler compatible with the host
libc.  The first fetch takes a few minutes; afterwards the result is cached
in the Bazel output base.  The same fixes that a source build needs on
modern gcc/glibc (gcc >= 10 -fno-common, C23, SIGSTKSZ) are applied via a
cc wrapper and a one-line patch, mirroring what Linux distributions do.
"""

_OCAML_VERSION = "4.08.1"
_OCAML_URL = "https://github.com/ocaml/ocaml/archive/4.08.1.tar.gz"
_OCAML_SHA256 = "b53ed3d487b83fd49bc181bded066ae8e6fb592cf40514261d27d36050d5db85"

# Fixes needed to build OCaml 4.08.x with modern toolchains. Applied through
# a wrapper around the host C compiler; equivalent to distro patches.
_CC_WRAPPER_FLAGS = "-std=gnu11 -fcommon"
_SIG_ALT_STACK_PATCH = "s/static char sig_alt_stack\\[SIGSTKSZ\\];/static char sig_alt_stack[32768];/"

_ELKHOUND_BASE = "https://github.com/The-Mod-Elephant/elkhound/releases/download/1.0.3/"
_ELKHOUND_ASSETS = {
    "linux": ("lin-elkhound", "142e7b202b2b69c06774ae8deb4caddff02cacc2d47313268400617b3c583c50"),
    "macos_intel": ("mac-elkhound", "c6ba1ab19b815364af7b3a92857b6abf0165d987c58328d7ff3f0d404bd6c744"),
    "macos_arm": ("mac-arm-elkhound", "152e11dcbedb5cba80bb6adf0fb633b7ea9007760cfa2598735a27bb642cd55b"),
    "windows": ("elkhound.exe", "6d40895e0c90af900fa7c39a921b642b237f2d747acb9e9c6d05f026afd2f2fb"),
}

_TOOLCHAIN_BUILD_TEMPLATE = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "tool_files",
    srcs = glob(["install/**"], allow_empty = True) + ["cc-wrapper.sh", "bash.sh"],
)

filegroup(name = "compiler", srcs = ["{compiler}"])
filegroup(name = "ocaml", srcs = ["install/bin/ocaml"])
filegroup(name = "ocamllex", srcs = ["install/bin/ocamllex"])
filegroup(name = "ocamlyacc", srcs = ["install/bin/ocamlyacc"])
filegroup(name = "bash", srcs = ["bash.sh"])
filegroup(name = "windres", srcs = {windres})
"""

def _default_path(host_path_sep):
    return "/usr/local/bin" + host_path_sep + "/usr/bin" + host_path_sep + "/bin"

def _ocaml_linux_toolchain_impl(repo_ctx):
    if repo_ctx.os.name != "linux":
        # Toolchain is only selected on Linux exec platforms; produce a stub.
        repo_ctx.file("BUILD.bazel", _TOOLCHAIN_BUILD_TEMPLATE.format(
            compiler = "install/bin/ocamlopt.opt",
            windres = "[]",
        ))
        return

    # Escape hatch: point at a prebuilt toolchain archive (URL or local path)
    # to skip the source build. Layout expectation: an "install/" prefix with
    # the standard OCaml install tree (bin/, lib/ocaml/).
    archive = repo_ctx.os.environ.get("WEIDU_OCAML_LINUX_ARCHIVE")
    if archive:
        if archive.startswith("http"):
            repo_ctx.download_and_extract([archive], "")
        else:
            repo_ctx.execute(["cp", "-r", archive + "/.", "install"])
        repo_ctx.file("bash.sh", "#!/bin/sh\nexec /bin/bash \"$@\"\n", executable = True)
        _write_linux_build(repo_ctx)
        return

    repo_ctx.download_and_extract(
        [_OCAML_URL],
        "src",
        sha256 = _OCAML_SHA256,
        stripPrefix = "ocaml-" + _OCAML_VERSION,
    )

    cc = repo_ctx.os.environ.get("WEIDU_OCAML_CC")
    if not cc:
        for candidate in ["gcc", "cc", "clang"]:
            found = repo_ctx.which(candidate)
            if found:
                cc = str(found)
                break
        if not cc:
            fail("ocaml_linux_toolchain: no C compiler found (gcc/cc/clang); " +
                 "a C compiler is required to build the OCaml toolchain, or set WEIDU_OCAML_CC.")

    repo_ctx.file("cc-wrapper.sh", "#!/bin/sh\nexec %s %s \"$@\"\n" % (cc, _CC_WRAPPER_FLAGS), executable = True)
    repo_ctx.execute(["chmod", "+x", "cc-wrapper.sh"])

    root = str(repo_ctx.path("."))
    env = {"PATH": root + ":" + _default_path(":")}
    prefix = root + "/install"

    # The one-line SIGSTKSZ patch (glibc >= 2.34 makes SIGSTKSZ non-constant).
    repo_ctx.execute(
        ["sed", "-i", _SIG_ALT_STACK_PATCH, "runtime/signals_nat.c"],
        working_directory = "src",
    )

    # Configure with CC looked up through PATH so the recorded name stays
    # relative ("cc-wrapper.sh") and resolves in action sandboxes later.
    conf = repo_ctx.execute(
        ["./configure", "--prefix=" + prefix],
        working_directory = "src",
        environment = dict(env, CC = "cc-wrapper.sh"),
        timeout = 1800,
    )
    if conf.return_code != 0:
        fail("ocaml_linux_toolchain: configure failed:\n%s" % conf.stderr)

    jobs = _nproc(repo_ctx)
    build = repo_ctx.execute(
        ["make", "world.opt", "-j%d" % jobs],
        working_directory = "src",
        environment = env,
        timeout = 5400,
    )
    if build.return_code != 0:
        fail("ocaml_linux_toolchain: make world.opt failed:\n%s" % build.stderr[-8000:])

    install = repo_ctx.execute(
        ["make", "install"],
        working_directory = "src",
        environment = env,
        timeout = 1800,
    )
    if install.return_code != 0:
        fail("ocaml_linux_toolchain: make install failed:\n%s" % install.stderr)

    # Make the cc wrapper reachable through the action PATH as well.
    repo_ctx.execute(["cp", "cc-wrapper.sh", "install/bin/cc-wrapper.sh"])

    repo_ctx.file("bash.sh", "#!/bin/sh\nexec /bin/bash \"$@\"\n", executable = True)
    _write_linux_build(repo_ctx)

def _write_linux_build(repo_ctx):
    compiler = "install/bin/ocamlopt.opt"
    if not repo_ctx.path(compiler).exists:
        compiler = "install/bin/ocamlopt"
    repo_ctx.file("BUILD.bazel", _TOOLCHAIN_BUILD_TEMPLATE.format(
        compiler = compiler,
        windres = "[]",
    ))

def _nproc(repo_ctx):
    res = repo_ctx.execute(["bash", "-c", "nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8"])
    out = res.stdout.strip()
    n = 8
    if out.isdigit():
        n = int(out)
    return max(1, min(32, n))

ocaml_linux_toolchain_repo = repository_rule(
    implementation = _ocaml_linux_toolchain_impl,
    environ = ["WEIDU_OCAML_LINUX_ARCHIVE", "WEIDU_OCAML_CC"],
    doc = "Builds the Linux OCaml 4.08.1 toolchain from upstream source on the host.",
)

# ---------------------------------------------------------------------------
# Windows toolchain (assembled from pinned MSYS2 archive packages)
# ---------------------------------------------------------------------------

# Historical MSYS2 mingw64 packages that together form a self-contained,
# Windows-native OCaml 4.14 + mingw-w64 gcc toolchain (OCaml >= 5 dropped
# -unsafe-string, so 4.14.x is the newest usable series; it is also what
# this project's own Windows CI uses).  Each entry: (repo path, sha256).
_MSYS2_MINGW_PACKAGES = [
    # populated in milestone 2 after verifying availability on repo.msys2.org
]

def _ocaml_windows_toolchain_impl(repo_ctx):
    if repo_ctx.os.name != "windows":
        # Stub: never selected on non-Windows exec platforms.
        repo_ctx.file("BUILD.bazel", _TOOLCHAIN_BUILD_TEMPLATE.format(
            compiler = "install/bin/ocamlopt.exe",
            windres = "[]",
        ))
        return
    fail("ocaml_windows_toolchain: Windows assembly not implemented yet (milestone 2).")

ocaml_windows_toolchain_repo = repository_rule(
    implementation = _ocaml_windows_toolchain_impl,
    doc = "Assembles the Windows OCaml toolchain from pinned MSYS2 archive packages.",
)

# ---------------------------------------------------------------------------
# elkhound parser generator (host-side tool, fetched per exec host)
# ---------------------------------------------------------------------------

def _elkhound_impl(repo_ctx):
    os_name = repo_ctx.os.name
    if os_name == "linux":
        asset = _ELKHOUND_ASSETS["linux"]
    elif os_name.startswith("mac"):
        arch = repo_ctx.execute(["uname", "-m"]).stdout.strip()
        asset = _ELKHOUND_ASSETS["macos_arm"] if arch == "arm64" else _ELKHOUND_ASSETS["macos_intel"]
    elif os_name.startswith("windows"):
        asset = _ELKHOUND_ASSETS["windows"]
    else:
        fail("elkhound: unsupported host OS '%s'" % os_name)

    name = asset[0]
    repo_ctx.download([_ELKHOUND_BASE + name], name, sha256 = asset[1])
    if not os_name.startswith("windows"):
        repo_ctx.execute(["chmod", "+x", name])

    repo_ctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

filegroup(name = "elkhound", srcs = ["%s"])
filegroup(name = "tool_files", srcs = ["%s"])
""" % (name, name))

elkhound_repo = repository_rule(
    implementation = _elkhound_impl,
    doc = "Fetches the elkhound parser generator binary for the exec host.",
)
