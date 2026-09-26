set -e
opts="--enable-analysis --enable-gzip --enable-pythia --enable-ufo --disable-pyext"
# Bundle sqlite3 — macOS ships the dylib but not the headers
opts="$opts --with-sqlite3=install"

# MPI causes build failures on macOS
if [ "$(uname)" = "Darwin" ]; then
  opts="$opts --disable-mpi"
fi

# Optional integrations — enabled automatically when the package is installed in hepyy
[ -n "{{ lhapdf_prefix }}"  ] && opts="$opts --enable-lhapdf={{ lhapdf_prefix }}"   && echo "[sherpa] LHAPDF6  : {{ lhapdf_prefix }}"
[ -n "{{ hepmc3_prefix }}"  ] && opts="$opts --enable-hepmc3={{ hepmc3_prefix }}"   && echo "[sherpa] HepMC3   : {{ hepmc3_prefix }}"
[ -n "{{ fastjet_prefix }}" ] && opts="$opts --enable-fastjet={{ fastjet_prefix }}" && echo "[sherpa] FastJet  : {{ fastjet_prefix }}"

echo "[sherpa] configure opts: $opts"
./configure --prefix={{ prefix }} $opts
make -j{{ n_cores }}
make install
