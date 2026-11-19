#!/bin/sh
# Build weidu.exe / weinstall.exe / tolower.exe inside the cross container,
# reusing the project's own GNU make build (Makefile + Configuration +
# Makefile.ocaml) rather than replicating its logic.
#
# Entry state: /work contains src.tar (the source tree: Makefile, Depends,
#              Configuration, Makefile.ocaml, src/, scripts/, elkhound/,
#              zlib/, xdiff/, glob/, fcase/, batteries-lite/,
#              hashtbl-4.03.0/, windows_resources/).
# Exit state:  weidu.exe, weinstall.exe, tolower.exe in /work/out.
set -e

WORK=/work
SRC="$WORK/src"

rm -rf "$SRC"
mkdir -p "$SRC"
tar -xf "$WORK/src.tar" -C "$SRC"

eval "$(opam env --switch cross --set-root --set-switch 2>/dev/null)"
SWITCH_BIN="$(opam var --switch cross bin)"
SYSROOT_BIN="$(opam var --switch cross prefix)/windows-sysroot/bin"

# Shim directory.  Configuration derives OCAMLDIR from `which ocaml.exe`, so
# every binary the Makefile invokes must resolve inside this one directory:
#   ocaml.exe / ocaml      -> host switch (codegen scripts run under it)
#   ocamlopt.opt           -> cross compiler (OCaml -> Windows .exe)
#   ocamllex/ocamlyacc/ocamldep -> host tools (output is target-agnostic)
#   elkhound.exe           -> host linux binary (the name is just a string)
SHIM=/opt/shims
mkdir -p "$SHIM"
ln -sf "$SWITCH_BIN/ocaml"         "$SHIM/ocaml"
ln -sf "$SWITCH_BIN/ocaml"         "$SHIM/ocaml.exe"
# The cross compiler is installed as ocamlrun-executed bytecode (the
# package's build.sh bootstraps with the host compiler), so there is no
# ocamlopt.opt; point the Makefile's `ocamlopt.opt` (USEOPT) at the
# sysroot's ocamlopt wrapper, which handles the flexdll PATH itself.
if [ -x "$SYSROOT_BIN/ocamlopt.opt" ]; then
  ln -sf "$SYSROOT_BIN/ocamlopt.opt" "$SHIM/ocamlopt.opt"
else
  ln -sf "$SYSROOT_BIN/ocamlopt" "$SHIM/ocamlopt.opt"
fi
ln -sf "$SWITCH_BIN/ocamllex"      "$SHIM/ocamllex"
ln -sf "$SWITCH_BIN/ocamlyacc"     "$SHIM/ocamlyacc"
ln -sf "$SWITCH_BIN/ocamldep"      "$SHIM/ocamldep"
ln -sf /opt/tools/lin-elkhound     "$SHIM/elkhound.exe"
export PATH="$SHIM:$PATH"

cd "$SRC"
mkdir -p obj/x86_WIN32 obj/.depend

# WINDIR      -> activates the win32 branch of Configuration (arch_mingw,
#                case_ins_win, createprocess_win32, glob_win32, reg,
#                WEIDU_ARCH=amd64, WINDRES_BIN=x86_64-w64-mingw32-windres)
# OS          -> activates the Windows link block in the Makefile (rc sed +
#                windres + resource object on the link line)
# HAVE_MINGW  -> explicit -ladvapi32 (the reg module itself is already added
#                by Configuration's win32 branch)
make WINDIR="C:/Windows" OS=Windows_NT HAVE_MINGW=yes weidu weinstall tolower

# Collect outputs under consumer-friendly names (upstream's windows_zip does
# the same rename: "weid*.exe -> WeiDU-Windows/weidu.exe").
mkdir -p "$WORK/out"
cp -f weidu.asm.exe     "$WORK/out/weidu.exe"
cp -f weinstall.asm.exe "$WORK/out/weinstall.exe"
cp -f tolower.asm.exe   "$WORK/out/tolower.exe"
