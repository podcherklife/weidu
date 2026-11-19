"""Docker-backed cross-compilation of the Windows executables.

Runs the container image defined in docker/win-cross (see that Dockerfile
for the supply-chain story) and drives the project's own GNU make build
inside it (docker/win-cross/build_weidu.sh).  Bazel owns input/output
wiring; the whole flow is ONE action:

  * the launcher bundles the declared sources (tar -T response file, so
    the command line stays tiny — cmd.exe has an ~8 KB limit),
  * builds the container image lazily (tagged with a content hash of the
    image definition),
  * feeds the bundle to the container and runs the make build,
  * copies the exes out of the exited container.

The action is plain `ctx.actions.run` (no genrule/run_shell anywhere) and
runs local/unsandboxed because it needs the host container runtime.

The launcher is exec-platform-dependent: a POSIX script on linux/macOS/CI
exec hosts, a cmd batch script on Windows exec hosts.  It is provided by
the `win_docker_launcher` repository rule below, which materializes the
right script for the exec host (repository rules always run on the exec
host, and select() cannot be used here: cfg = "exec" attributes still
evaluate their selects against the target platform).  Consumers point
the `launcher` attribute at the fixed label `@win_docker_launcher//:launcher`.
"""

_LAUNCHER_POSIX = """\
#!/bin/bash
# WeiduDockerBuild launcher (POSIX exec hosts: docker first, podman
# fallback).
#
# Args: src_tar dockerfile build_script out_weidu out_weinstall out_tolower
#       paths_file
# The action runs unsandboxed, so paths are execroot-relative and real.
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

src_tar=$1; dockerfile=$2; build_script=$3
out_weidu=$4; out_weinstall=$5; out_tolower=$6
paths_file=$7

# Bundle the declared sources.  -h dereferences: exec-root staging may use
# symlinks, and the bundle must carry real file contents (and no host
# paths); -T keeps the command line tiny regardless of source count.
tar -chf "$src_tar" -T "$paths_file"

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

_LAUNCHER_WIN = r"""\
@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem WeiduDockerBuild launcher (Windows exec hosts: docker.exe via Docker
rem Desktop first, then docker inside WSL2).  Every container command runs
rem with relative paths from a staging directory -- no bind mounts and no
rem path conversion, so the same flow works whether the runtime is a
rem Windows docker or `wsl.exe -e docker` (wsl.exe inherits the current
rem directory as /mnt/...).
rem Args: %1=src_tar %2=dockerfile %3=build_script %4..6=out exes
rem       %7=paths_file

set "SRC_TAR=%~1"
set "DOCKERFILE=%~2"
set "BUILD_SCRIPT=%~3"
set "OUT_WEIDU=%~4"
set "OUT_WEINSTALL=%~5"
set "OUT_TOLOWER=%~6"
set "PATHS_FILE=%~7"

rem --- pick a container runtime ------------------------------------------
set "DOCKER_CMD=docker"
docker info >nul 2>&1
if errorlevel 1 (
    wsl.exe -e docker info >nul 2>&1
    if errorlevel 1 (
        echo ERROR: no working container runtime ^(tried docker.exe, wsl.exe -e docker^). 1>&2
        echo The Windows exe cross-build needs Docker Desktop running, or 1>&2
        echo docker-ce installed and started inside the default WSL2 distro. 1>&2
        exit /b 1
    )
    set "DOCKER_CMD=wsl.exe -e docker"
)

rem --- image tag from content hashes of the image definition -------------
rem (Distinct from the POSIX tag formula by design: the image lives in a
rem different daemon per host OS, so tag sharing never matters.)
set "TAG=weidu-win-cross"
for /f %%h in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%DOCKERFILE%').Hash.Substring(0,16).ToLower()"') do set "TAG=!TAG!-%%h"
for /f %%h in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%BUILD_SCRIPT%').Hash.Substring(0,16).ToLower()"') do set "TAG=!TAG!-%%h"

rem --- stage inputs; all docker commands below use relative paths ---------
set "STAGE=%TEMP%\weidu-win-cross-%RANDOM%%RANDOM%"
mkdir "%STAGE%" || goto :fail1
copy /y "%DOCKERFILE%" "%STAGE%\Dockerfile" >nul || goto :fail1
copy /y "%BUILD_SCRIPT%" "%STAGE%\build_weidu.sh" >nul || goto :fail1
pushd "%STAGE%" || goto :fail1

rem --- bundle the sources (Windows ships bsdtar as tar.exe) ---------------
tar -cf src.tar -T "%PATHS_FILE%" || goto :fail2

%DOCKER_CMD% image inspect %TAG% >nul 2>&1
if errorlevel 1 (
    echo Building cross-compile image %TAG% ^(one-time, ~20 min on a cold cache^)...
    %DOCKER_CMD% build -t %TAG% .
    if errorlevel 1 goto :fail2
)

set "CTR=weidu-bazel-build-%RANDOM%%RANDOM%"
%DOCKER_CMD% create --name %CTR% %TAG% >nul || goto :fail2
%DOCKER_CMD% cp src.tar %CTR%:/work/src.tar || goto :fail3
%DOCKER_CMD% start -a %CTR% || goto :fail3
%DOCKER_CMD% cp %CTR%:/work/out/weidu.exe weidu.exe || goto :fail3
%DOCKER_CMD% cp %CTR%:/work/out/weinstall.exe weinstall.exe || goto :fail3
%DOCKER_CMD% cp %CTR%:/work/out/tolower.exe tolower.exe || goto :fail3
popd

rem --- move outputs into their declared (execroot-relative) paths ---------
for %%F in ("%OUT_WEIDU%" "%OUT_WEINSTALL%" "%OUT_TOLOWER%") do (
    if not exist "%%~dpF" mkdir "%%~dpF"
)
copy /y "%STAGE%\weidu.exe" "%OUT_WEIDU%" >nul || goto :fail3
copy /y "%STAGE%\weinstall.exe" "%OUT_WEINSTALL%" >nul || goto :fail3
copy /y "%STAGE%\tolower.exe" "%OUT_TOLOWER%" >nul || goto :fail3
rem the declared bundle output (same directory as the exes)
copy /y "%STAGE%\src.tar" "%SRC_TAR%" >nul || goto :fail3

%DOCKER_CMD% rm -f %CTR% >nul 2>&1
popd 2>nul
rd /s /q "%STAGE%" 2>nul
exit /b 0

:fail3
%DOCKER_CMD% rm -f %CTR% >nul 2>&1
:fail2
popd 2>nul
:fail1
rd /s /q "%STAGE%" 2>nul
exit /b 1
"""

def _win_docker_launcher_impl(repo_ctx):
    # Repository rules always run on the exec host, so the host OS decides
    # which launcher is materialized.
    if repo_ctx.os.name.startswith("win"):
        repo_ctx.file("launcher.bat", _LAUNCHER_WIN, executable = True)
        launcher = "launcher.bat"
    else:
        repo_ctx.file("launcher.sh", _LAUNCHER_POSIX, executable = True)
        launcher = "launcher.sh"
    repo_ctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["{launcher}"])

alias(name = "launcher", actual = ":{launcher}")
""".format(launcher = launcher))

win_docker_launcher_repo = repository_rule(
    implementation = _win_docker_launcher_impl,
    doc = "Materializes the WeiduDockerBuild launcher script for the exec host.",
)

def _weidu_win_docker_impl(ctx):
    out_weidu = ctx.actions.declare_file("win-docker/weidu.exe")
    out_weinstall = ctx.actions.declare_file("win-docker/weinstall.exe")
    out_tolower = ctx.actions.declare_file("win-docker/tolower.exe")
    outs = [out_weidu, out_weinstall, out_tolower]
    src_tar = ctx.actions.declare_file("win-docker/src.tar")

    # Response file for `tar -T`: one source path per line, keeping the
    # action's command line tiny (cmd.exe has an ~8 KB limit).
    paths_file = ctx.actions.declare_file("win-docker/srcs.list")
    paths_lines = ""
    for f in ctx.files.srcs:
        paths_lines += f.path + "\n"
    ctx.actions.write(paths_file, paths_lines)

    ctx.actions.run(
        executable = ctx.executable.launcher,
        arguments = [
            src_tar.path,
            ctx.file.dockerfile.path,
            ctx.file.build_script.path,
            out_weidu.path,
            out_weinstall.path,
            out_tolower.path,
            paths_file.path,
        ],
        inputs = depset(
            [ctx.file.dockerfile, ctx.file.build_script, paths_file] +
            list(ctx.files.srcs),
        ),
        outputs = outs + [src_tar],
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
        # Exec-host-appropriate launcher script from the
        # win_docker_launcher repository (see above).
        "launcher": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
    },
)
