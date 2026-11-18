# Native payload wheels

This build path is separate from `heyy install`: it produces pip-owned payloads
with no registry entries, no cppyy runtime, and no independent Python bindings.
Existing source recipes and their installation behavior are unchanged. Their
cppyy headers/namespaces are reused; the wheel manifests explicitly select the
actual shared libraries shipped in each payload.

## Build

Use Python >=3.12, `pip install wheel pyyaml`, a C++17 compiler and make. Linux
also needs patchelf and a manylinux build image. Pythia's installer needs rsync.
macOS needs Xcode command line tools (install_name_tool and codesign).

```sh
python wheels/build.py fastjet --work build-native --cache cache --output wheelhouse
python wheels/build.py fjcontrib --work build-native --cache cache --output wheelhouse \
  --fastjet-prefix build-native/fastjet/prefix
python wheels/build.py pythia8 --work build-native --cache cache --output wheelhouse
python wheels/verify.py wheelhouse/*.whl
```

Each build needs a fresh work directory for that package. Download archives are
cached separately and checked against SHA-256 values pinned in `build.py`.
FastJet 3.5.1 enables the C++ plugins (no Fortran dependency); fjcontrib 1.102
uses upstream's `fragile-shared` target to create one contrib shared library.
It contains contrib code, not FastJet itself. Pythia 8.317 has no optional
FastJet/HepMC/LHAPDF link dependencies; its events pass to FastJet through cppyy.

Wheel versions append a packaging revision to the upstream version. These
`py3-none-<platform>` wheels have no CPython ABI dependency, but do have C++ ABI
requirements. C++17, the platform standard library, and the explicit FastJet ABI
generation must match. Linux uses `_GLIBCXX_USE_CXX11_ABI=1`. fjcontrib pins
`hepyy-fastjet==3.5.1.0` in metadata and its FastJet ABI generation in the manifest.
Bump both when changing that ABI/build contract.

Only headers, shared libraries, runtime data, manifests, and original license
notices are packaged. No static archives, libtool archives, build tools, or
cppyy/Cling libraries are shipped. Each shared library is stored once under its SONAME/install identity. The
manifest tells the loader to use that canonical filename, avoiding duplicate
images from pip copying symlink aliases. No FastJet libraries appear in the
contrib wheel. The smoke test checks the loaded process images explicitly.

macOS install names use `@loader_path`; the contrib dependency points to the
sibling `hepyy_fastjet/lib`. Linux uses the corresponding `$ORIGIN` rpaths.
Run auditwheel repair inside the matching manylinux image, excluding the three
FastJet SONAMEs when repairing contrib so they are not copied into a second wheel.
Do not retag an arbitrary local Linux build as manylinux.

## Compatibility gate and CI

The Actions workflow builds manylinux_2_28 x86_64 and macOS arm64/x86_64 artifacts.
It tests Linux pip cppyy with Python 3.10/3.12, and activated macOS conda-forge
cppyy with Python 3.12. The paired hepyy revision is pinned in the workflow;
update it deliberately after merging the loader changes. Artifacts are uploaded
only after successful checks; **there is no PyPI publish job**.

`smoke.py` verifies STL JIT, C++ std::string interoperability, FastJet clustering
and momentum conservation, SoftDrop, Nsubjettiness, and three seeded Pythia events
through the shared cppyy types. Tests must run with an empty hepyy registry and
without access to build prefixes. A local macOS arm64 run also passed with
Python 3.14 and conda-forge cppyy 3.5.0. macOS deployment tags are build targets;
they do not by themselves establish runtime support on every older macOS release.

The native wheels are not published. Install the paired hepyy checkout with
`pip install --find-links wheelhouse './hepyy[fjcontrib,pythia8]'` in an activated
conda-forge cppyy environment, or add the `cppyy` extra on tested Linux pip hosts.
Source tarball redistribution, license/source delivery obligations, additional
architectures, and minimum OS validation need release review before publication.
