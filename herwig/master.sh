set -e

curl -sL "https://herwig.hepforge.org/downloader?f=herwig-bootstrap" -o herwig-bootstrap
chmod +x herwig-bootstrap

python3 -m pip install --quiet cython six "setuptools==65.7.0"

opts=""

# Pin to recipe version; "master" skips this and uses the bootstrap default
[ "{{ version }}" != "master" ] && opts="$opts --herwig-version={{ version }}"

# Reuse hepyy-installed packages where available
[ -n "{{ lhapdf_prefix }}"  ] && opts="$opts --with-lhapdf={{ lhapdf_prefix }}"
[ -n "{{ fastjet_prefix }}" ] && opts="$opts --with-fastjet={{ fastjet_prefix }}"
[ -n "{{ hepmc3_prefix }}"  ] && opts="$opts --with-hepmc={{ hepmc3_prefix }}"

# Set HERWIG_BOOTSTRAP_LITE=1 to skip NLO tools (GoSam, MadGraph, OpenLoops, Rivet, ...)
[ -n "$HERWIG_BOOTSTRAP_LITE" ] && opts="$opts --lite"

echo "[herwig] bootstrap opts: $opts"

python3 ./herwig-bootstrap -j{{ n_cores }} $opts --src-dir={{ srcdir }}/src {{ prefix }}

# Restore setuptools after GoSam's pinned version
python3 -m pip install --quiet --upgrade setuptools
