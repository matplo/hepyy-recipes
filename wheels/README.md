# Native hepbundle wheels

The wheel profiles package FastJet, fjcontrib, HepMC3, LHAPDF (including upstream
Python bindings and lhapdf command), and Pythia8 with FastJet/HepMC3/LHAPDF6
interfaces. Exact versions are recorded in packages.lock.json. All share their native dependency
libraries and the existing cppyy loader. No alternative cppyy runtime is bundled.

See [UPGRADING.md](UPGRADING.md) for the explicit recipe-driven sync/run/build/
status/promote commands, version rules, supported build profiles and CI gates.
[RELEASE.md](RELEASE.md) describes publisher setup and promotion approval.
[REBUILD.md](REBUILD.md) describes the corresponding source materials delivered
inside every wheel. The first full bundle is available with hepyy 0.2.31;
see [public installation instructions](https://github.com/matplo/hepyy/blob/main/NATIVE_WHEELS.md).

Linux uses manylinux x86_64 builds; macOS builds arm64 and Intel. LHAPDF's
Python binding is cp310-abi3, audited and runtime-tested. Other payloads are
py3-none-platform wheels. All retain upstream notices and exact source archives.
The data-manager script is installed as a normal console entry point by pip.

Source recipe additions retain older versions for reproducibility. The hepbundle
recipe now selects fjcontrib 1.105. Wheel versions/dependency pins come from
packages.lock.json generated from the recipes; they are not repeated in the
builder or CI version tables. A changed recipe produces a fresh tested bundle
cohort so index artifacts are never overwritten. Unknown new package profiles
are rejected until their native build and tests have been reviewed.
