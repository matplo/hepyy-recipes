set -euo pipefail

prefix="{{ prefix }}"
source_dir="{{ srcdir }}/jewel-cpp"
build_dir="{{ builddir }}/cmake-build"
# The v0.2.0 tag predates the Python bindings.
revision=f4a8826583431c1a531a3692aec5ba345081b6e9
repository=git@github.com:matplo/jewel-cpp.git

# hepyy's recipe builder resolves depends_on from its source registry. Use
# wheel metadata here so an install reuses the active Python environment.
wheel_prefix() {
    python - "$1" <<'PY'
import sys
from hepyy.native import wheel_record

name = sys.argv[1]
record = wheel_record(name)
if record is None:
    sys.exit(f"Missing hepyy-{name} wheel. Run: python -m pip install 'hepyy[hepbundle]'")
print(record["prefix"])
PY
}

pythia8_prefix=$(wheel_prefix pythia8)
lhapdf_prefix=$(wheel_prefix lhapdf)

git init --quiet "$source_dir"
if ! git -C "$source_dir" cat-file -e "$revision^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch --no-tags --depth 1 "$repository" "$revision"
fi
git -C "$source_dir" checkout --quiet --detach "$revision"

cmake_env=(env)
cmake_args=()
{% if platform == 'darwin' %}
# Build against the same Apple toolchain as the native wheels.
cmake_env+=(-u CXXFLAGS -u CPPFLAGS -u LDFLAGS)
cmake_args+=(-DCMAKE_CXX_COMPILER="$(xcrun --find clang++)")
{% endif %}
"${cmake_env[@]}" cmake -S "$source_dir" -B "$build_dir" \
    "${cmake_args[@]}" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DJEWEL_WITH_PYTHIA8=ON \
    -DJEWEL_WITH_CPPYY=ON -DJEWEL_PYTHIA8_ROOT="$pythia8_prefix" \
    -DJEWEL_LHAPDF_ROOT="$lhapdf_prefix"
cmake --build "$build_dir" --target jewel_generator --parallel "{{ n_cores }}"
cmake --install "$build_dir"

example_dir="$prefix/share/jewel-cpp/examples"
mkdir -p "$example_dir"
cp "$source_dir/examples/jewel_fastjet.py" "$source_dir/examples/jewel_fastjet.ipynb" "$example_dir/"
cp "$source_dir/README.md" "$example_dir/../README.md"
