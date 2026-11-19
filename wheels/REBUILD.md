# Rebuilding the native payload

This wheel supplies its exact, unmodified upstream release archive, original
license notices, the packaging build script and the package's YAML recipe.
The packaging script is MIT licensed (PACKAGING-LICENSE); upstream software
retains its original licenses. Inspect the upstream COPYING/LICENSE files for
component terms and citation requests. No upstream source changes are applied;
fjcontrib's lowercase `version` files are renamed during compilation to avoid
shadowing the standard C++ header.

To use this source snapshot, make this directory the `wheels` directory under a
new root. Move the upstream archive into a sibling `cache` directory, retain the
package recipe at `<root>/<package>/<upstream-version>.yaml`, and run from root:

```sh
python -m pip install wheel pyyaml
python wheels/build.py fastjet --work build-native --cache cache --output wheelhouse
```

Substitute `pythia8` for that package. For fjcontrib, build the matching FastJet
3.5.1 source first with the FastJet wheel's supplied materials, then run:

```sh
python wheels/build.py fjcontrib --work build-native --cache cache --output wheelhouse \
  --fastjet-prefix build-native/fastjet/prefix
```

Use Python >=3.12, make and a C++17 compiler; Linux needs patchelf and rsync.
macOS needs Xcode command line tools and MACOSX_DEPLOYMENT_TARGET=11.0.
Portable Linux wheels must be built/audited in the project's manylinux image.
`provenance.json` records the upstream hash, compiler and CI source revision.
The public repository contains the full CI, auditwheel commands and tests:
https://github.com/matplo/hepyy-recipes/tree/main/wheels

This is a corresponding-source snapshot, not a pip-buildable source distribution.
The exact original tarball is included so it can also be built using upstream's
own build and installation instructions, independent of the wheel builder.
