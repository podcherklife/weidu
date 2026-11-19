# Windows cross-compile toolchain image for WeiDU.
#
# Runs the project's own GNU make build (Makefile + Configuration +
# Makefile.ocaml) inside the image and emits weidu.exe, weinstall.exe and
# tolower.exe into /work/out.  Usage (no bind mounts, so this also works
# from Windows hosts via WSL2 docker):
#
#   docker create --name weidu-build weidu-win-cross:<tag>
#   docker cp src.tar weidu-build:/work/src.tar
#   docker start -a weidu-build
#   docker cp weidu-build:/work/out/weidu.exe .
#   docker rm weidu-build
#
# The compiler story:
#   * host OCaml 4.14.1 (switch "cross") runs the codegen scripts
#     (scripts/make_tph.ml & co.) and provides host lex/yacc/dep tools;
#   * the mingw-w64 cross-compiler (ocaml-windows64) compiles/links the
#     Windows exes.
#   * OCaml 4.14's configure enables force-safe-string by default, which
#     rejects the -unsafe-string flag WeiDU's Makefile passes everywhere.
#     The host switch therefore uses ocaml-option-default-unsafe-string --
#     exactly like the project's own Windows CI
#     (.github/workflows/main.yaml) -- and the cross package is installed
#     from a local overlay repo whose build.sh carries
#     --disable-force-safe-string.  Both are distro-style compatibility
#     settings, not behavior changes.
#
# Supply chain: everything is fetched from public upstreams (digest-pinned
# ubuntu base, Ubuntu archive packages, the pinned opam-cross-windows
# commit -- verified by hash after a shallow clone -- whose compiler
# package builds the official github.com/ocaml/ocaml 4.14.1 tarball, and
# the same pinned elkhound release asset used by bazel/ocaml/repos.bzl and
# .github/workflows/main.yaml).  The overlay repo is byte-identical to the
# upstream package definitions except for the one configure flag.  Nothing
# is hosted by this repository.
FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

ENV DEBIAN_FRONTEND=noninteractive OPAMYES=1 OPAMROOT=/root/.opam

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git make m4 perl patch unzip zip rsync pkg-config file \
      gcc-mingw-w64-x86-64 opam \
    && rm -rf /var/lib/apt/lists/*

RUN opam init -a --bare --disable-sandboxing -y

# Clone the pinned opam-cross-windows commit and verify it (fails the build
# if the repository moved).
RUN git clone --depth 1 https://github.com/ocaml-cross/opam-cross-windows.git /opt/cross-src \
 && test "$(git -C /opt/cross-src rev-parse HEAD)" = "7817f871e2cd490e3230a8666d3a063ec54fab79"

# Overlay repo: the exact dependency closure of the cross compiler
# (conf-gcc-windows64, flexdll-windows, ocaml-windows64), with
# ocaml-windows64's build.sh carrying one added configure flag
# (--disable-force-safe-string; its md5 entry dropped from the opam file
# accordingly).  Disjoint from the default opam repository, so there is no
# repo precedence ambiguity.
RUN mkdir -p /opt/opam-overlay/packages/ocaml-windows64 \
 && cp -r /opt/cross-src/packages/conf-gcc-windows64 /opt/opam-overlay/packages/ \
 && cp -r /opt/cross-src/packages/flexdll-windows /opt/opam-overlay/packages/ \
 && cp -r /opt/cross-src/packages/ocaml-windows64/ocaml-windows64.4.14.1 /opt/opam-overlay/packages/ocaml-windows64/ \
 && sed -i 's/--enable-systhreads/--enable-systhreads --disable-force-safe-string/' /opt/opam-overlay/packages/ocaml-windows64/ocaml-windows64.4.14.1/files/build.sh \
 && sed -i "s/md5=0c02dc9cf4fa5bb98b8771d22ffd15d9/md5=$(md5sum /opt/opam-overlay/packages/ocaml-windows64/ocaml-windows64.4.14.1/files/build.sh | cut -d' ' -f1)/" /opt/opam-overlay/packages/ocaml-windows64/ocaml-windows64.4.14.1/opam \
 && printf 'opam-version: "2.0"\n' > /opt/opam-overlay/repo \
 && opam repository add overlay /opt/opam-overlay --set-default

# Host compiler (codegen scripts) with the same unsafe-string configuration
# the project's own Windows CI uses.  --packages defines the switch
# invariant (the documented way to create a switch with an ocaml-option-*).
RUN opam switch create cross --packages=ocaml-variants.4.14.1+options,ocaml-option-default-unsafe-string -y

# The mingw64 cross-compiler itself (~15 min build).
RUN opam install -y --switch cross ocamlfind ocaml-windows64.4.14.1

# elkhound parser generator (host-side codegen tool; same pinned asset as
# bazel/ocaml/repos.bzl and .github/workflows/main.yaml).
RUN mkdir -p /opt/tools \
 && curl -fsSL https://github.com/The-Mod-Elephant/elkhound/releases/download/1.0.3/lin-elkhound -o /opt/tools/lin-elkhound \
 && echo "142e7b202b2b69c06774ae8deb4caddff02cacc2d47313268400617b3c583c50  /opt/tools/lin-elkhound" | sha256sum -c - \
 && chmod +x /opt/tools/lin-elkhound

COPY build_weidu.sh /opt/win-cross/build_weidu.sh

WORKDIR /work
# /work exists in the image filesystem itself: the source bundle is fed
# via stdin (`cat > /work/src.tar` inside the container), and `docker cp`
# of the outputs out of the exited container needs nothing extra.  No
# ENTRYPOINT: the invoking launcher passes the full container command.
RUN mkdir -p /work /work/out
