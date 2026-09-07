set -e

# Ensure setuptools is available for the pip source build backend, and pin
# cmake <4.0.0: cmake 4.x changed if() argument parsing in a way that breaks
# cppyy-cling 6.32.8's CMakeLists.txt:189 ('Unknown arguments specified').
# pip otherwise auto-installs the latest cmake as a build dep.
pip install setuptools wheel "cmake<4.0.0" --quiet

mkdir -p {{ builddir }}/cppyy-cling-wheels
SRC_DIR={{ builddir }}/cppyy-cling-src

if [[ "$(uname)" == "Darwin" ]]; then
  # ------------------------------------------------------------------ macOS
  # Two independent problems when building cppyy-cling 6.32.8 (LLVM/cling 16)
  # from source against the current (Xcode 16+/macOS 26.x) SDK:
  #
  #   1. Bundled zlib's zutil.h matches modern Darwin via the legacy
  #      TARGET_OS_MAC clause (meant for pre-OS X "Classic" Mac toolchains,
  #      which TARGET_OS_MAC — from <TargetConditionals.h> — also happens to
  #      be defined on) and clobbers the real fdopen() with a macro that
  #      discards it, breaking macOS 26.x _stdio.h's own fdopen()
  #      declaration ('expected identifier or (' at compile time). One-line
  #      patch: drop the TARGET_OS_MAC half of the #if. Upstream ROOT
  #      already made this exact fix in 6.36.08.
  #
  #   2. Cling's *own* embedded Clang-16-era frontend (part of Cling's
  #      source, distinct from whatever compiler builds Cling) cannot parse
  #      the current SDK's libc++ headers (missing builtins like
  #      __builtin_clzg) — this hits even during the build itself, in
  #      rootcling's dictionary generation (core/G__CoreLegacy.cxx), not
  #      just at first 'import cppyy' at runtime. Fix: point the *entire*
  #      build at an older Command Line Tools SDK via SDKROOT, so Cling
  #      only ever sees headers it understands. This bakes the fix into the
  #      built libCling permanently — no SDKROOT override needed afterward.
  OLD_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk \
                   /Library/Developer/CommandLineTools/SDKs/MacOSX14*.sdk \
                   /Library/Developer/CommandLineTools/SDKs/MacOSX13*.sdk \
            2>/dev/null | sort -V | tail -1)
  if [ -z "$OLD_SDK" ]; then
    echo "[cppyy-cling] -------------------------------------------------------"
    echo "[cppyy-cling] FATAL: cling 16 (LLVM 16) cannot parse the current macOS"
    echo "[cppyy-cling] SDK's libc++ headers, and no older (<=15.x) SDK was found"
    echo "[cppyy-cling] under /Library/Developer/CommandLineTools/SDKs/."
    echo "[cppyy-cling]"
    echo "[cppyy-cling] Fix: install an older SDK alongside the current Command"
    echo "[cppyy-cling] Line Tools (they coexist fine), or wait for cppyy 3.6+"
    echo "[cppyy-cling] (LLVM 17+)."
    echo "[cppyy-cling] -------------------------------------------------------"
    exit 1
  fi
  SDK_VER=$(basename "$OLD_SDK" .sdk | sed 's/MacOSX//')
  echo "[cppyy-cling] Building against older SDK for Cling compatibility: $OLD_SDK"
  export SDKROOT="$OLD_SDK" MACOSX_DEPLOYMENT_TARGET="$SDK_VER"
  _compiler_msg="$(c++ --version | head -1)"

  # pip has no hook to patch a version-spec ('pip install cppyy-cling==X')
  # build in place, so download + extract + patch + build from that local
  # directory instead.
  rm -rf "$SRC_DIR" {{ builddir }}/cppyy-cling-sdist
  mkdir -p "$SRC_DIR" {{ builddir }}/cppyy-cling-sdist
  pip download cppyy-cling=={{ version }} --no-binary cppyy-cling --no-deps \
      -d {{ builddir }}/cppyy-cling-sdist --no-cache-dir --quiet
  tar xzf {{ builddir }}/cppyy-cling-sdist/cppyy_cling-{{ version }}.tar.gz -C "$SRC_DIR"
  sed -i.bak \
      's/#if defined(MACOS) || defined(TARGET_OS_MAC)/#if defined(MACOS)/' \
      "$SRC_DIR/cppyy_cling-{{ version }}/src/builtins/zlib/zutil.h"
  BUILD_TARGET="$SRC_DIR/cppyy_cling-{{ version }}"
else
  # ------------------------------------------------------------------ Linux
  # Prefer g++/gcc explicitly — on SUSE/RHEL the default 'c++' may point to
  # an old system GCC (e.g. 7.5.0) while 'g++' is a newer GCC 13+.
  export CXX=g++ CC=gcc
  _compiler_msg="$(g++ --version | head -1)"
  BUILD_TARGET="cppyy-cling=={{ version }}"
fi

echo "[cppyy-cling] Building LLVM + cling from source with ${_compiler_msg}"
echo "[cppyy-cling] cmake: $(cmake --version | head -1)"
echo "[cppyy-cling] The sdist bundles the full LLVM + cling source tree (~13k files)."
echo "[cppyy-cling] Expect 30-90 min and up to 10 GB temporary disk space."

# Uninstall the pre-built binary wheel
pip uninstall -y cppyy cppyy-backend cppyy-cling 2>/dev/null || true

# Build cppyy-cling from source, installing to heppyyier-managed prefix.
#
# Two-step build via --no-build-isolation: 'pip install --no-binary' alone
# still builds inside an *isolated* PEP 517 env, which re-resolves cmake
# fresh (ignoring the cmake<4 pin above) and hits the same CMakeLists.txt:189
# failure. --no-build-isolation makes the build use this venv's own cmake/
# setuptools/wheel directly.
# STDCXX=17: use C++17 (required; 20 is the default on non-manylinux)
# MAKE_NPROCS: parallelism for the cmake build
STDCXX=17 MAKE_NPROCS={{ n_cores }} \
pip wheel "$BUILD_TARGET" \
    --no-build-isolation \
    --no-cache-dir \
    --no-deps \
    -w {{ builddir }}/cppyy-cling-wheels \
    --verbose

pip install cppyy-cling=={{ version }} \
    --find-links {{ builddir }}/cppyy-cling-wheels \
    --no-cache-dir \
    --force-reinstall \
    --target {{ prefix }}

# Verify — packages are in {{ prefix }}, not site-packages.
# libCling is a .dylib on macOS and a .so on Linux.
PYTHONPATH={{ prefix }} python3 -c "
import cppyy_backend, pathlib, sys
base = pathlib.Path(cppyy_backend.__file__).parent / 'lib'
lib = next((base / n for n in ('libCling.dylib', 'libCling.so') if (base / n).exists()), None)
print('[cppyy-cling] backend:', cppyy_backend.__file__)
print('[cppyy-cling] libCling:', lib.name if lib else 'NOT FOUND')
if lib is None:
    sys.exit(1)
"

# Write installation info to the heppyyier prefix for registry tracking
PYTHONPATH={{ prefix }} python3 -c "import cppyy_backend, pathlib; pathlib.Path('{{ prefix }}/.cling_install').write_text(str(pathlib.Path(cppyy_backend.__file__).parent))"
echo "[cppyy-cling] Build complete."
