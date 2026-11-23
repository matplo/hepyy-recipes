# hepyy-recipes

Recipe collection for [hepyy](https://github.com/matplo/hepyy) — a local HEP C++ package manager.

Recipes are automatically fetched when you run `hepyy init`. To refresh:

```bash
hepyy recipe update
```

## Available recipes

| Package | Version | Description |
|---------|---------|-------------|
| boost | 1.87.0 | Boost C++ libraries |
| dpmjet | 19.3.7 | DPMJET-III nucleus-nucleus / hadron-nucleus event generator (requires gfortran) |
| fastjet | 3.5.1 | Jet finding (FastJet) |
| fjcontrib | 1.102 | FastJet contrib — SoftDrop, Nsubjettiness, EnergyCorrelator |
| gsl | 2.8 | GNU Scientific Library |
| hepmc3 | 3.3.1 | HepMC3 event record I/O |
| herwig | 7.3.0 | Herwig 7 event generator — bootstrap-based full install (requires lhapdf; set `HERWIG_BOOTSTRAP_LITE=1` to skip NLO tools) |
| herwig | master | Herwig 7 — bootstrap default version (requires lhapdf) |
| hepyy-utils | main | Workflow utilities for hepyy-installed generators and tools |
| jewel | 2.6.0-custom | JEWEL 2.6.0: stock binaries, `jewel-2.6.0-custom-{simple,vac}` with hard-parton output and optional production geometry, and `jewel-2.6.0-custom-perf-{simple,vac}` with performance patches (requires lhapdf) |
| jewel | 2.6.0 | JEWEL jet quenching event generator (requires lhapdf) |
| jewel | 2.4.0 | JEWEL jet quenching event generator (requires lhapdf) |
| jewel | 2.2.0 | JEWEL jet quenching event generator (requires lhapdf) |
| jewel-cpp | 0.2.0 | Standalone C++ JEWEL generator with Pythia8, a cppyy interface, and FastJet examples |
| lhapdf | 6.5.5 | LHAPDF6 PDF sets with Python (SWIG) bindings |
| lhapdf | 6.5.4 | LHAPDF6 PDF sets with Python (SWIG) bindings |
| powheg | v2 | POWHEG-BOX-V2 NLO event generator (requires svn; fetches source via SVN) |
| pythia8 | 8.317 | Pythia8 event generator |
| root | 6.40.00 | ROOT data analysis framework |
| roounfold | 3.0.5 | RooUnfold unfolding library (requires root) |
| roounfold | master | RooUnfold — GitLab master (requires root) |
| sherpa | 2.2.15 | Sherpa 2 multi-purpose event generator (optional: lhapdf, hepmc3, fastjet) |
| starlight | master | STARlight ultra-peripheral collision generator (optional: hepmc3, dpmjet) |

## C++ JEWEL in Python

Activate the Conda environment or venv where you will run the examples. Install
the native wheels with `python -m pip install 'hepyy[hepbundle]'`. If the
environment also needs cppyy, use `hepyy[cppyy,hepbundle]`. Building the recipe
requires Git, CMake, a C++17 compiler, and GitHub SSH access to the private
`matplo/jewel-cpp` repository. The recipe pins the Python bindings commit after
`v0.2.0` and builds against the active environment’s Pythia8 and LHAPDF wheels.

```bash
hepyy recipe update
hepyy install jewel-cpp
python -c 'import hepyy; hepyy.load("jewel_cpp"); import jewel_cpp; print(jewel_cpp.EventGeneratorConfig())'
```

From a local checkout of this recipe collection, use
`hepyy install jewel-cpp --recipe "$PWD/jewel-cpp/0.2.0.yaml"`.
The install command uses `jewel-cpp`, and the Python import is `jewel_cpp`.
The `jewel` recipes below build the Fortran generator.

```bash
jewel_examples=$(python -c 'from hepyy.registry import get_registry; print(get_registry().get("jewel_cpp")["prefix"] + "/share/jewel-cpp/examples")')
python "$jewel_examples/jewel_fastjet.py"
jupyter notebook "$jewel_examples/jewel_fastjet.ipynb"
```

Run the notebook with a kernel from the same environment. The recipe registers
`jewel_cpp` automatically. The notebook’s linked CMake and registry setup is
for a manual build. Both examples generate hadronized events and cluster
anti-kt jets with hepyy’s FastJet.

## JEWEL production geometry and path estimates

The `2.6.0-custom` recipe includes `geometry-v1` in both the `custom` and
`custom-perf` binary pairs. The stock pair is unchanged. Geometry output is
disabled by default and supports `COLLIDER PPJJ` dijets. Enable it for an
otherwise configured run with:

```bash
JEWEL_GEOMETRY_FILE=run.geometry.csv \
JEWEL_GEOMETRY_RUN_ID=medium-run-001 \
JEWEL_GEOMETRY_STEP_FM=0.02 \
jewel-2.6.0-custom-perf-simple params.dat
```

The output path must not exist. Use a unique run ID beginning with a letter or
digit and containing only letters, digits, `_`, `.`, or `-` (maximum 128
characters). The optional step must be positive and finite; its default is
`0.02`. Extremely small steps requiring more than ten million integration
intervals per leg fail explicitly. Unsupported colliders and invalid output
settings fail instead of silently omitting the diagnostics.

Each successfully written HepMC event has exactly two contiguous CSV rows,
identified by its HepMC `event_id` and stable `leg_id` 1 or 2. The file header
records the schema (`jewel_geometry_v1`), run ID, medium, coordinate frame,
integration step, and medium settings. Join using **run ID plus event ID**;
event numbers alone are not unique across runs.

The production point is shared by the two outgoing legs: `x0_fm,y0_fm`, with
`z0_fm=t0_fm=0`. `b_fm` is the actual sampled impact parameter; `centrality` is
the generator's fractional centrality (0–1). The collision frame has the
impact parameter along x and the beam along z. Four-momenta and temperatures
use GeV, positions/lengths use fm, and time uses fm/c. These are explicit
sidecar units; the existing HepMC file still declares millimetres.

| Fields | Definition |
|--------|------------|
| `pid`, `me_px,me_py,me_pz,me_e` | The saved matrix-element partons also written as status 23 in short HepMC output; before JEWEL's virtuality and momentum reshuffling. |
| `px,py,pz,e` | Shower-start momenta after virtuality setup and before cascade evolution; these define the path axes. |
| `L_geom_T_fm` | Straight transverse distance to exit the overlap of the two finite `NTHICK` supports, using the thickness table's actual maximum radius. Independent of temperature or lifetime. |
| `L_hot_fm` | Three-dimensional distance along the straight shower-start ray for which the actual `GETTEMP` is positive, bounded by the generator's `GETLTIMEMAX` and geometric exit. |
| `L_hot_T_fm` | Transverse projection of that same hot path. |
| `int_T3_dl` | Integral of `T^3 dl` over the hot path, in GeV³·fm; a diagnostic, not an identification with JEWEL's transport coefficient. |

The deterministic midpoint integration covers the full bounded time interval,
including the medium's initial temperature rise. It does not stop at the first
zero temperature. The step bounds coordinate time in fm/c and hence distance
in fm; refine it to check numerical convergence. Vacuum output uses zero
lengths/integrals, `b_fm=0`, and `centrality=-1`.

These are **primary-leg straight-ray estimates**, not accumulated paths of all
shower branches or unique ancestry labels for final jets. Associate them with
reconstructed jets using an explicit matching rule and keep unmatched or
ambiguous cases. Final leading/subleading ordering need not equal leg 1/2, and
status-23 diagnostics must not be clustered as physical constituents.

The exact CSV columns are:

```text
event_id,leg_id,pid,weight,b_fm,centrality,x0_fm,y0_fm,z0_fm,t0_fm,me_px,me_py,me_pz,me_e,px,py,pz,e,L_geom_T_fm,L_hot_fm,L_hot_T_fm,int_T3_dl
```

Geometry adds no random draws and is designed to leave HepMC events and RNG
state unchanged. The recipe checks all modified source hashes, installs
`custom-geometry.patch` alongside the other patches and lists the complete
patch set in `info/CUSTOM-PATCHES.txt`. Rebuild an existing `2.6.0-custom`
installation to obtain this patch; the package version has not changed.

Analytic estimator tests can be run with `python -m unittest discover -s tests`
(requires `gfortran`). For a full build and paired export-off/export-on checks:

```bash
python tests/validate_jewel_geometry.py \
  --source-dir /path/to/unpacked/jewel-2.6.0 \
  --lhapdf-prefix /path/to/lhapdf \
  --work-dir /path/to/new/validation-directory
```

This requires Jinja2 and the CT14nlo PDF set. It checks unchanged HepMC and
final RNG state for vacuum/medium, custom/performance, recoil, long-output,
and mixed-isospin cases, as well as path-step convergence. All builds and
generation take place in the new work directory. Optional `--tables-dir`
reuses `splitint.dat`, `pdfs.dat`, and `xsecs.dat` produced with matching
settings; optional `--fixtures-dir` saves compact real reference samples.

## Recipe format

Each recipe is a YAML file at `<name>/<version>.yaml`. See existing recipes for the format.
To contribute, open a pull request against this repository.

## Pip-installable HEP bundle

[The native wheel builder](wheels/README.md) packages FastJet, fjcontrib, HepMC3,
LHAPDF (with its upstream Python API and command), and Pythia8 with their shared
native interfaces. The full bundle is available through `hepyy[hepbundle]`;
see [installation](https://github.com/matplo/hepyy/blob/main/NATIVE_WHEELS.md).
[The upgrade program](wheels/UPGRADING.md) prepares new candidates from recipe
changes. CI builds and tests artifacts; a separate, protected promotion workflow
publishes approved releases. Source installation remains available.
