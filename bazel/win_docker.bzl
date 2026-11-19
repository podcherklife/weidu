"""Docker-backed cross-compilation of the Windows executables.

Runs the container image defined in docker/win-cross (see that Dockerfile
for the supply-chain story) and drives the project's own GNU make build
inside it (build_weidu.sh).  Bazel owns input/output wiring:

  * Action 1 bundles the declared sources into a tar (sandboxed and
    disk-cacheable like any normal action).
  * Action 2 runs the container dance (create -> cp -> start -> cp -> rm)
    with execution_requirements {"local", "no-sandbox"} because it needs
    the host container runtime; the image is built lazily and tagged by a
    content hash of the Dockerfile + build script, so image rebuilds only
    happen when the image definition changes.

Both actions are plain `ctx.actions.run` calls on generated launcher
scripts (no genrule/run_shell anywhere).  Linux exec hosts only for now:
the launcher picks a working runtime (`docker`, falling back to
`podman`).  Windows-host execution (docker.exe / WSL2 via a cmd-based
launcher) is a follow-up; until then the rule fails on a Windows exec
host with a missing-bash style error.
"""

_LAUNCHER = """\
#!/bin/bash
# WeiduDockerBuild launcher.
# Args: src_tar dockerfile build_script out_weidu out_weinstall out_tolower
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

src_tar=$1; dockerfile=$2; build_script=$3
out_weidu=$4; out_weinstall=$5; out_tolower=$6

# Pick a working container runtime (docker first, podman as fallback).
RT=""
for c in docker podman; do
  if command -v "$c" >/dev/null 2>&1 && "$c" info >/dev/null 2>&1; then
    RT="$c"; break
  fi
done
if [ -z "$RT" ]; then
  echo "ERROR: no working container runtime (tried docker, podman)." >&2
  echo "The Windows exe cross-build needs a running docker or podman." >&2
  exit 1
fi

# Image tag = content hash of the image definition (Dockerfile + build
# script); the image is built lazily, only when the tag is absent.
tag="weidu-win-cross:$(cat "$dockerfile" "$build_script" | sha256sum | cut -c1-16)"

ctr="weidu-bazel-build-$$-$RANDOM"
ctxdir=""
cleanup() {
  "$RT" rm -f "$ctr" >/dev/null 2>&1 || true
  if [ -n "$ctxdir" ]; then rm -rf "$ctxdir"; fi
}
trap cleanup EXIT

if ! "$RT" image inspect "$tag" >/dev/null 2>&1; then
  ctxdir=$(mktemp -d)
  cp "$dockerfile" "$ctxdir/Dockerfile"
  cp "$build_script" "$ctxdir/build_weidu.sh"
  echo "Building cross-compile image $tag (one-time, ~20 min on a cold cache)..."
  "$RT" build -t "$tag" "$ctxdir"
fi

mkdir -p "$(dirname "$out_weidu")"
# Feed the source bundle via stdin and run the project's make build as the
# container command; `run` streams output and propagates the exit code.
# The exes are copied out of the exited container afterwards (cp into a
# created-but-never-started container is not reliable, e.g. rootless
# podman, so nothing is ever cp'd in).
"$RT" run -i --name "$ctr" "$tag" /bin/sh -c 'cat > /work/src.tar && exec /bin/sh /opt/win-cross/build_weidu.sh' < "$src_tar"
"$RT" cp "$ctr:/work/out/weidu.exe" "$out_weidu"
"$RT" cp "$ctr:/work/out/weinstall.exe" "$out_weinstall"
"$RT" cp "$ctr:/work/out/tolower.exe" "$out_tolower"
"""

_BUNDLER = """\
#!/bin/bash
# WeiduDockerBundle launcher: tar the declared sources into $1.
# Args: out_tar src1 src2 ...
# -h dereferences: bazel stages action inputs as absolute symlinks inside
# the sandbox, and the bundle must contain the real file contents (both so
# the container build can read them and so no host paths leak into it).
set -euo pipefail
export PATH=/usr/bin:/bin
out=$1
shift
tar -chf "$out" "$@"
"""

def _weidu_win_docker_impl(ctx):
    out_weidu = ctx.actions.declare_file("win-docker/weidu.exe")
    out_weinstall = ctx.actions.declare_file("win-docker/weinstall.exe")
    out_tolower = ctx.actions.declare_file("win-docker/tolower.exe")
    outs = [out_weidu, out_weinstall, out_tolower]
    src_tar = ctx.actions.declare_file("win-docker/src.tar")

    src_files = ctx.files.srcs

    # Action 1: source bundle (sandboxed, cacheable).
    bundler = ctx.actions.declare_file("win-docker/bundle.sh")
    ctx.actions.write(bundler, _BUNDLER, is_executable = True)
    ctx.actions.run(
        executable = bundler,
        arguments = [src_tar.path] + [f.path for f in src_files],
        inputs = depset(src_files),
        outputs = [src_tar],
        mnemonic = "WeiduDockerBundle",
        use_default_shell_env = False,
        progress_message = "Bundling sources for the Windows cross-build",
    )

    # Action 2: container orchestration (local, unsandboxed).
    launcher = ctx.actions.declare_file("win-docker/launcher.sh")
    ctx.actions.write(launcher, _LAUNCHER, is_executable = True)
    ctx.actions.run(
        executable = launcher,
        arguments = [src_tar.path,
                     ctx.file.dockerfile.path,
                     ctx.file.build_script.path] + [o.path for o in outs],
        inputs = depset([src_tar, ctx.file.dockerfile, ctx.file.build_script]),
        outputs = outs,
        mnemonic = "WeiduDockerBuild",
        execution_requirements = {"local": "1", "no-sandbox": "1"},
        use_default_shell_env = True,  # the runtime needs HOME/sockets/config
        progress_message = "Cross-compiling Windows exes via docker/win-cross",
    )

    # DefaultInfo executable = the primary exe, so rules that declare an
    # executable dep (e.g. the sanity check) get a single file.
    return [DefaultInfo(
        files = depset(outs),
        executable = out_weidu,
    )]

weidu_win_docker = rule(
    implementation = _weidu_win_docker_impl,
    attrs = {
        # The complete tracked source tree the make build consumes
        # (explicit list: stale gitignored generated files must not leak in).
        "srcs": attr.label_list(mandatory = True, allow_files = True),
        "dockerfile": attr.label(mandatory = True, allow_single_file = True),
        "build_script": attr.label(mandatory = True, allow_single_file = True),
    },
)
