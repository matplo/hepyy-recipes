# Upgrade the pip bundle from recipes

Run this tool explicitly after adding/updating recipes. It selects the highest
stable numeric recipe for each member of hepbundle, computes and verifies source
hashes, and prepares a version-locked candidate. It does not poll in the background.

## One local preparation command

Use an activated build venv with Python >=3.12 and:

```sh
python -m pip install wheel pyyaml packaging Cython==3.3.1 twine abi3audit
python wheels/upgrade.py run \
  --hepyy-root /path/to/hepyy \
  --cache /path/to/source-cache \
  --work /path/to/new-build-directory \
  --output /path/to/candidate-wheelhouse
```

Linux additionally needs a C++17 compiler, make, cmake, rsync, patchelf and the
manylinux build image for portable release wheels. macOS needs Xcode tools and
cmake. The native installers stage only under --work; Python and staging paths
are passed explicitly. Nothing installs into the build interpreter's global
site-packages. LHAPDF's upstream Cython bindings are built separately against the
same staged LHAPDF library and audited for CPython's stable ABI.

This command synchronizes packages.lock.json, updates hepyy's native extras,
hepbundle extra, built-in recipe copies and public-release dependency lock, then
builds all five packages in dependency order and checks the resulting wheels.
Use a fresh --work directory; existing build trees are never silently deleted.
Inspect both Git diffs, commit the candidate and run CI before any upload.
The hepyy project release version remains an explicit maintainer choice.

For smaller steps:

```sh
# Preview (downloads/checks source archives, edits no repository files):
python wheels/upgrade.py sync --cache /path/to/source-cache --index https://pypi.org
# Write the reviewed plan and paired hepyy metadata:
python wheels/upgrade.py sync --cache /path/to/source-cache --write \
  --hepyy-root /path/to/hepyy --index https://pypi.org
# Compare exact locked versions with either package index:
python wheels/upgrade.py status --index https://pypi.org
python wheels/upgrade.py requirements
```

## Version and ABI rules

Upstream versions come from recipes, not a second handwritten version table in
the wheel builder. A packaging revision is appended (e.g. FastJet 3.5.3 becomes
hepyy-fastjet 3.5.3.N). Source, recipe/script, native dependency and build-profile
changes are fingerprinted. Running sync again without changes is a no-op.

An input change prepares a new **whole-bundle candidate**: unchanged upstream
releases also receive fresh packaging revisions. This avoids rebuilding new
bytes under immutable, already-published PyPI filenames and records one coherent
set of tested native dependencies. Index lookups skip occupied version numbers
for changed inputs. The existing lock is part of source control and must be
retained between upgrades. Old release files and tags are never overwritten.

Pythia's new candidate includes the FastJet, HepMC3 and external LHAPDF6
interfaces/plugins and pins the matching native wheels. ABI checks reject
source/shell libraries mixed with wheel plugins. The LHAPDF Python module and
lhapdf command link to that same LHAPDF library; no second native copy is bundled.
LHAPDF wheels use cp310-abi3 tags and require CPython >=3.10. Other payloads have
no CPython extension ABI. The CI matrix validates the actual APIs and command.
PDF sets are downloaded data, not bundled wholesale; tests use pinned CT14lo.

There are five reviewed build profiles. A new package in hepbundle is rejected
until its build, relocation and integration tests are added. Recipe upgrades
that need new flags, a new compiler or changed upstream APIs still require
review and may fail CI; the program does not guess such compatibility changes.

## Test and promote

CI builds Linux x86_64 and macOS arm64/Intel wheels. It checks hashes, licenses,
source delivery, metadata, stable Python ABI, native provider identity, real
LHAPDF PDF evaluation, lhapdf version/list/install/show, Pythia external LHAPDF,
HepMC3 event conversion/file roundtrip, FastJet adapter and fjcontrib observables.

After reviewing/merging the paired changes, require a successful main-push CI
run at the exact release commit. The paired hepyy revision in CI is an explicit
commit pin: update it after committing the synchronized hepyy changes.

```sh
python wheels/upgrade.py promote --run-id SUCCESSFUL_MAIN_RUN --index testpypi
```

This dispatches the existing protected workflow; it does not approve its
required-reviewer gates. TestPyPI installations are then retested on all targets.
The workflow requires protected publisher environments for every package before
uploading anything. See RELEASE.md for publisher fields; HepMC3 and LHAPDF need
hepyy-hepmc3/hepyy-lhapdf publishers and matching *-hepmc3/*-lhapdf environments.

Public promotion is separate and must be explicitly approved:

```sh
python wheels/upgrade.py promote --run-id SAME_SUCCESSFUL_MAIN_RUN --index pypi
```

hepyy's release tag is created only after all native dependencies are on PyPI.
There is no automatic public upload on a recipe commit or a sync/run invocation.
