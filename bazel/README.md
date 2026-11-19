# Bazel build for weidu-augmented

This repository is consumable as a Bazel module that produces the WeiDU
executables — `weidu`, `weinstall`, `tolower` — for both unix and Windows
target platforms.  Everything the build needs is fetched from public
upstream sources; nothing is hosted by this repository, and the produced
artifacts are byte-for-byte the output of this project's own GNU make
build (Makefile + Depends + Configuration), just orchestrated by Bazel.

## Quickstart (Bazel overlay consumers)

In the consuming project's `MODULE.bazel`:

```python
bazel_dep(name = "weidu_augmented", version = "25201.0.0")

# Until the module is published to the Bazel Central Registry, pin the
# source directly:
git_override(
    module_name = "weidu_augmented",
    remote = "https://github.com/podcherklife/weidu.git",
    commit = "<full commit sha>",
)
```

Then build/reference the executables:

```sh
bazel build @weidu_augmented//:weidu            # native for the target platform
bazel build @weidu_augmented//:weidu --platforms=//platforms:windows_x86_64
```

`//:weidu`, `//:weinstall` and `//:tolower` are platform-dispatched
aliases: on unix target platforms they resolve to the native OCaml build,
on the `windows_x86_64` target platform to the container cross-build
(`//:weidu_win_docker`).  Reference them by label — e.g. via
`$(rlocationpath @weidu_augmented//:weidu)` in `data`/`env` wiring — and
the correct binary for the selected platform comes out; never reach into
`bazel-bin` paths, whose spelling differs per platform
(`weidu_native` vs `win-docker/weidu.exe`).

## Consuming the exes from Java (e2e tests)

```python
java_test(
    name = "my_e2e_test",
    data = ["@weidu_augmented//:weidu"],
    env = {"WEIDU_BIN": "$(rlocationpath @weidu_augmented//:weidu)"},
    deps = ["@bazel_tools//tools/java/runfiles"],
)
```

```java
String weidu = Runfiles.preferDevSources().rlocation(System.getenv("WEIDU_BIN"));
```

## What each platform needs

| Target platform | Exec host | Requirements |
|---|---|---|
| unix (default) | any linux/macOS | host `gcc` (or `cc`/`clang`), `make`, `bash` — for the one-time OCaml toolchain source build |
| `windows_x86_64` | linux/CI (or any host with docker) | a working `docker` or `podman` |
| `windows_x86_64` | Windows host | not yet: the container launcher is a POSIX script; a cmd-based Windows-exec launcher is planned |

First-fetch behavior:

* **unix targets**: the OCaml 4.08.1 toolchain is compiled from upstream
  source on the host (a few minutes, once; afterwards served from the
  Bazel repository cache / external cache).
* **windows target**: the cross-compile image (`docker/win-cross/`) is
  built lazily on first use (~20 min on a cold cache — it compiles the
  mingw OCaml cross-compiler) and tagged with a content hash of its
  definition, so it is rebuilt only when `docker/win-cross/` changes.

## CI caching (for consumers that build this module on CI)

The working reference is `.github/workflows/bazel.yml` in this repo:

* `bazel-contrib/setup-bazel` with an external-cache manifest entry
  caches the assembled Linux toolchain repo, keyed on
  `bazel/ocaml/repos.bzl`:

  ```yaml
  external-cache: |
    ocaml_toolchain_linux: bazel/ocaml/repos.bzl
  ```

* the cross-compile image is cached via `actions/cache` (a
  `docker save`/`docker load` tarball keyed on
  `hashFiles('docker/win-cross/Dockerfile', 'docker/win-cross/build_weidu.sh')`).

## Targets

| Target | Purpose |
|---|---|
| `//:weidu`, `//:weinstall`, `//:tolower` | platform-dispatched aliases — the ones consumers should use |
| `//:weidu_native`, `//:weinstall_native`, `//:tolower_native` | native unix builds (what the aliases resolve to on unix targets) |
| `//:weidu_win_docker` | container cross-build (manual-tagged; produces `win-docker/*.exe`) |
| `//:sanity` | build-time functional check of the native `weidu` (version banner, D→DLG→D round trip, bad-input rejection) |
| `//:sanity_win` | the same assertions against the cross-built exe, run through `wine` (manual; hosts need wine installed) |

## Supply chain

Everything is fetched from public upstreams and pinned:

* OCaml 4.08.1 source — `github.com/ocaml/ocaml` release tarball, sha256
  pinned; the hash is independently recorded by the opam repository for
  `ocaml-base-compiler.4.08.1`.
* elkhound parser generator — the 1.0.3 release assets referenced by the
  project's own `.github/workflows/main.yaml`, sha256 pinned.
* Windows cross toolchain — `ocaml-cross/opam-cross-windows` at a pinned
  commit (hash-verified after a shallow clone); its compiler package
  builds the official `github.com/ocaml/ocaml` 4.14.1 tarball.
* Container base — `ubuntu:24.04` pinned by manifest digest.

The trust contract: consumers only need to trust the Bazel/Starlark and
Docker files in this repository plus the public upstreams above.  The
single local delta to upstream package definitions is the
`--disable-force-safe-string` configure flag on the cross compiler —
the same compatibility the project's own Windows CI gets through
`ocaml-option-default-unsafe-string`, because OCaml 4.14's `configure`
enables force-safe-string by default while WeiDU's Makefile passes
`-unsafe-string` throughout.

## Architecture notes

* `bazel/ocaml/` — repository rules (toolchains, elkhound) and the
  minimal Starlark rule set driving the native OCaml build; module
  compilation follows the exact `Depends` order with a conservative
  over-approximated dependency chain.
* `bazel/win_docker.bzl` — the container cross-build: a sandboxed,
  cacheable source-bundle action plus an unsandboxed docker/podman
  orchestration action (runtime detection, content-hash image tag,
  stdin-fed container run).
* `platforms/BUILD.bazel` — the target platform definitions used by the
  `select()` dispatch and `--platforms` overrides.
