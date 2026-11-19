# Rebuilding the native payload

This wheel supplies its exact, unmodified upstream release archive, original
license notices, the packaging build script and the package's YAML recipe.
The packaging script is MIT licensed (PACKAGING-LICENSE); upstream software
retains its original licenses. Inspect the upstream COPYING/LICENSE files for
component terms and citation requests. The original source archive is unmodified. The build script records the small
build-time adjustments: lowercase fjcontrib version files are renamed to avoid
shadowing C++ headers; Pythia's HepMC plugin receives explicit portable linking;
LHAPDF bindings are regenerated with Cython 3.3.1 for the CPython 3.10 stable ABI
and installed with relative library paths. The CLI uses HTTPS and honors local
source precedence. All adjustment code is included beside this document.

To use this source snapshot, make this directory the `wheels` directory under a
new root. Move the upstream archive into a sibling `cache` directory, retain the
package recipe at `<root>/<package>/<upstream-version>.yaml`, and run from root:

```sh
python -m pip install wheel pyyaml packaging Cython==3.3.1
python wheels/build.py fastjet --work build-native --cache cache --output wheelhouse
```

Substitute the desired package name. Build matching native dependencies from
this lock first, using each dependency wheel's supplied source materials.
For fjcontrib, build FastJet 3.5.3 first, then run:

```sh
python wheels/build.py fjcontrib --work build-native --cache cache --output wheelhouse \
  --fastjet-prefix build-native/fastjet/prefix
```

For Pythia8, build FastJet, HepMC3 and LHAPDF first, then run:

```sh
python wheels/build.py pythia8 --work build-native --cache cache --output wheelhouse \
  --dependency-prefix fastjet=build-native/fastjet/prefix \
  --dependency-prefix hepmc3=build-native/hepmc3/prefix \
  --dependency-prefix lhapdf=build-native/lhapdf/prefix
```

Use Python >=3.12, make, cmake and a C++17 compiler; Linux needs patchelf and rsync.
macOS needs Xcode command line tools and MACOSX_DEPLOYMENT_TARGET=11.0.
Portable Linux wheels must be built/audited in the project's manylinux image.
`provenance.json` records the upstream hash, compiler and CI source revision.
The public repository contains the full CI, auditwheel commands and tests:
https://github.com/matplo/hepyy-recipes/tree/main/wheels

This is a corresponding-source snapshot, not a pip-buildable source distribution.
The exact original tarball is included so it can also be built using upstream's
own build and installation instructions, independent of the wheel builder.
