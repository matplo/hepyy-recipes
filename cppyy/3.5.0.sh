set -e

pip uninstall -y cppyy cppyy-backend cppyy-cling CPyCppyy 2>/dev/null || true

if [[ "$(uname)" == "Darwin" ]]; then
  # ------------------------------------------------------------------ macOS
  # cppyy-cling 6.32.8 (LLVM/cling 16) needs two fixes to build from source
  # against the current (Xcode 16+/macOS 26.x) SDK — see cppyy-cling/6.32.8.sh
  # for the full explanation of both:
  #   1. cmake<4 pin + --no-build-isolation (CMakeLists.txt:189 breaks on
  #      cmake 4.x's stricter if() parsing).
  #   2. A one-line zutil.h patch — bundled zlib's legacy TARGET_OS_MAC clause
  #      wrongly matches modern Darwin and clobbers fdopen() with a macro.
  #
  # On top of that, Cling's *own* embedded Clang-16-era frontend can't parse
  # the current SDK's libc++ headers at all (a separate problem from what
  # built Cling — Cling acts as its own compiler at runtime). This shows up
  # even during the build, in rootcling's dictionary generation. Point the
  # *entire* build at an older Command Line Tools SDK via SDKROOT so Cling
  # only ever sees headers it understands — this bakes the fix into the
  # built libCling permanently, with no SDKROOT override needed afterward
  # (verified: a cppyy built this way successfully JIT-compiles and runs
  # std::vector code with zero runtime environment changes).
  pip install setuptools wheel "cmake<4.0.0" --quiet

  OLD_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk \
                   /Library/Developer/CommandLineTools/SDKs/MacOSX14*.sdk \
                   /Library/Developer/CommandLineTools/SDKs/MacOSX13*.sdk \
            2>/dev/null | sort -V | tail -1)
  if [ -z "$OLD_SDK" ]; then
    echo "[cppyy] -------------------------------------------------------"
    echo "[cppyy] FATAL: cling 16 (LLVM 16) cannot parse the current macOS"
    echo "[cppyy] SDK's libc++ headers, and no older (<=15.x) SDK was found"
    echo "[cppyy] under /Library/Developer/CommandLineTools/SDKs/."
    echo "[cppyy]"
    echo "[cppyy] Fix: install an older SDK alongside the current Command"
    echo "[cppyy] Line Tools (they coexist fine), or wait for cppyy 3.6+"
    echo "[cppyy] (LLVM 17+)."
    echo "[cppyy] -------------------------------------------------------"
    exit 1
  fi
  SDK_VER=$(basename "$OLD_SDK" .sdk | sed 's/MacOSX//')
  echo "[cppyy] Building cppyy-cling against older SDK for Cling compatibility: $OLD_SDK"
  export SDKROOT="$OLD_SDK" MACOSX_DEPLOYMENT_TARGET="$SDK_VER"
  echo "[cppyy] Compiler: $(c++ --version | head -1)"
  echo "[cppyy] cmake:    $(cmake --version | head -1)"

  # pip has no hook to patch a version-spec ('pip install cppyy-cling==X')
  # build in place, so download + extract + patch + build from that local
  # directory instead.
  SRC_DIR={{ builddir }}/cppyy-cling-src
  rm -rf "$SRC_DIR" {{ builddir }}/cppyy-cling-sdist
  mkdir -p "$SRC_DIR" {{ builddir }}/cppyy-cling-sdist
  pip download cppyy-cling==6.32.8 --no-binary cppyy-cling --no-deps \
      -d {{ builddir }}/cppyy-cling-sdist --no-cache-dir --quiet
  tar xzf {{ builddir }}/cppyy-cling-sdist/cppyy_cling-6.32.8.tar.gz -C "$SRC_DIR"
  sed -i.bak \
      's/#if defined(MACOS) || defined(TARGET_OS_MAC)/#if defined(MACOS)/' \
      "$SRC_DIR/cppyy_cling-6.32.8/src/builtins/zlib/zutil.h"

  echo "[cppyy] Building cppyy-cling from source (~30-90 min)..."
  mkdir -p {{ builddir }}/cppyy-wheels
  STDCXX=17 MAKE_NPROCS={{ n_cores }} \
  pip wheel "$SRC_DIR/cppyy_cling-6.32.8" \
      --no-build-isolation \
      --no-cache-dir \
      --no-deps \
      -w {{ builddir }}/cppyy-wheels

  echo "[cppyy] Installing cppyy stack..."
  pip install "cppyy=={{ version }}" \
      --find-links {{ builddir }}/cppyy-wheels \
      --no-cache-dir \
      --force-reinstall \
      --target {{ prefix }}

else
  # ------------------------------------------------------------------ Linux
  # Two-step source build to work around pip 26.x not propagating
  # PIP_CONSTRAINT into nested isolated build environments.
  # Step 1: pip wheel --no-build-isolation uses the venv's cmake<4 directly.
  # Step 2: pip install --find-links installs from the pre-built wheel.
  pip install setuptools wheel "cmake<4.0.0" --quiet

  if command -v g++ &>/dev/null; then
    export CXX=g++ CC=gcc
  fi
  echo "[cppyy] Compiler: $(${CXX:-c++} --version | head -1)"
  echo "[cppyy] cmake:    $(cmake --version | head -1)"

  echo "[cppyy] Building cppyy-cling wheel from source (~30-90 min)..."
  mkdir -p {{ builddir }}/cppyy-wheels
  STDCXX=17 MAKE_NPROCS={{ n_cores }} \
  pip wheel "cppyy-cling==6.32.8" \
      --no-binary cppyy-cling \
      --no-build-isolation \
      --no-cache-dir \
      --no-deps \
      -w {{ builddir }}/cppyy-wheels

  echo "[cppyy] Installing cppyy stack..."
  pip install "cppyy=={{ version }}" \
      --find-links {{ builddir }}/cppyy-wheels \
      --no-cache-dir \
      --force-reinstall \
      --target {{ prefix }}
fi

# ------------------------------------------------------------------ verify
# PYTHONPATH must include {{ prefix }} since packages land there, not site-packages.
PYTHONPATH={{ prefix }} python3 -c \
  "import cppyy, cppyy_backend, pathlib, sys; \
   base = pathlib.Path(cppyy_backend.__file__).parent / 'lib'; \
   lib = next((base / n for n in ('libCling.dylib', 'libCling.so') if (base / n).exists()), None); \
   print('[cppyy]', cppyy.__version__, '- libCling:', lib.name if lib else 'NOT FOUND'); \
   sys.exit(0 if lib else 1)"

echo "{{ version }}" > {{ prefix }}/.cppyy_install
echo "[cppyy] Done."
