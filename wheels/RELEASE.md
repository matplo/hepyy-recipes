# Release a locked hepbundle candidate

The versions and exact native dependency graph are in packages.lock.json. Use
`python wheels/upgrade.py requirements` to print the candidate requirements.
The current upstream set is FastJet 3.5.3, fjcontrib 1.105, HepMC3 3.3.1,
LHAPDF 6.5.5 and Pythia 8.317 with all three external interfaces. The expanded
candidate is not published yet. Previously staged three-package TestPyPI
artifacts are older candidates and must never be overwritten.

## Account setup

All publishers use owner/repository matplo/hepyy-recipes and workflow filename
publish-native.yml. Configure the following exact environment names:

| Project | TestPyPI environment | PyPI environment |
|---|---|---|
| hepyy-fastjet | testpypi | pypi |
| hepyy-fjcontrib | testpypi-fjcontrib | pypi-fjcontrib |
| hepyy-hepmc3 | testpypi-hepmc3 | pypi-hepmc3 |
| hepyy-lhapdf | testpypi-lhapdf | pypi-lhapdf |
| hepyy-pythia8 | testpypi-pythia8 | pypi-pythia8 |

FastJet/fjcontrib/Pythia publishers were registered previously. HepMC3 and LHAPDF
are new registrations requiring owner approval/setup. Pending publisher tuples
must be distinct across project names. Each GitHub environment must require
matplo review and allow only main. The prepare job checks all environments
before uploading any package. Do not rely on automatically created, unprotected
environments. Verify publisher names again before the first upload; pending
publishers do not reserve names.

hepyy's publisher uses matplo/hepyy, publish.yml, environment pypi. Its environment
requires matplo review and permits v* tags. The pre-change snapshot
pre-pip-wheels-2026-11-18 must never be moved.

## Candidate and release sequence

1. Run the preparation described in UPGRADING.md. Inspect the lock, source
   hashes, packaging revisions, ABI/dependency changes and paired Git diffs.
   The build profiles are reviewed policies; incompatible upstream changes
   require fixes and tests, not guessed flags. Set the intended hepyy release
   version explicitly. No command here creates a release tag automatically.
2. Commit/review the paired changes. Pin the synchronized hepyy commit in native
   CI and TestPyPI rehearsal. Merge only after tests pass.
3. Require successful Native wheels CI on the exact recipes main release
   commit: Linux build/audit, Linux Python3.10/3.12 and macOS arm64/Intel. There
   must be fifteen wheels, one per package/platform. LHAPDF is cp310-abi3 and
   includes the upstream Python API and lhapdf command; other payloads have no
   CPython extension ABI. Original licenses/sources/build adjustments are shipped.
4. After TestPyPI upload approval, dispatch:
   `python wheels/upgrade.py promote --run-id SUCCESSFUL_MAIN_RUN --index testpypi`.
   The protected workflow verifies CI identity, the complete locked matrix,
   source hashes/license files/metadata, and checksums. It publishes FastJet,
   then HepMC3/LHAPDF, then fjcontrib/Pythia8 through package-specific approvals.
5. Follow all four TestPyPI installation rehearsals to completion. They install
   normal dependencies separately, download exact native versions only from
   TestPyPI (never mixed extra indexes), preserve cppyy, and run real scientific
   checks and lhapdf CLI/API tests. Record hashes and successful jobs.
6. Obtain explicit public-release approval for that locked set and checksums.
   Dispatch the same successful main run to index pypi and approve the public
   environments. A partial upload needs an inspected deliberate retry; the
   workflow does not blindly skip existing files or overwrite versions.
7. Verify public native installs. Only then obtain/create the approved new hepyy
   version tag; its existing release workflow checks that every locked native
   version and platform is on PyPI before publishing hepyy. Recheck tag/version
   availability. Verify the public pip commands in clean environments.

Neither a recipe commit nor sync/run publishes. The promote subcommand only
dispatches a workflow; required-reviewer approval is still enforced. Standard
first-release targets are Linux x86_64 and macOS arm64/Intel, CPython >=3.10 for
the complete bundle. Additional OS/architecture claims need validation. Existing
source builds remain available; native wheel source archives are corresponding
source snapshots, not pip-buildable native sdists.
