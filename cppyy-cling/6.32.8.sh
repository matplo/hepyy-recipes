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

# Build cppyy-cling from source, installing to hepyy-managed prefix.
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

# Write installation info to the hepyy prefix for registry tracking
PYTHONPATH={{ prefix }} python3 -c "import cppyy_backend, pathlib; pathlib.Path('{{ prefix }}/.cling_install').write_text(str(pathlib.Path(cppyy_backend.__file__).parent))"
echo "[cppyy-cling] Build complete."
