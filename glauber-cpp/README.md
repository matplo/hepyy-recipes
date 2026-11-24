# Glauber CLI wheel releases

The `Glauber CLI wheels` workflow builds the package from the public
`glauber-cpp` checkout pinned in `wheels.lock.json`. It builds macOS
arm64 and Intel wheels and a manylinux x86_64 wheel. Each test installs
the hepyy extra in a new environment, runs the installed CLI, and passes
its generated Pb–Pb CSV to a JEWEL runner built against hepbundle.

The shared `publish-native.yml` workflow promotes the three wheels from
a successful build on the same recipes commit. Supply the build run ID,
choose `package_set=glauber-cpp` and `destination=pypi`, and set
`verify_only=true` for a dry run. Uploading requires review in the
`pypi-glauber-cpp` GitHub environment.

| PyPI Trusted Publisher field | Value |
|---|---|
| Project name | `hepyy-glauber-cpp` |
| Owner | `matplo` |
| Repository | `hepyy-recipes` |
| Workflow name | `publish-native.yml` |
| Environment name | `pypi-glauber-cpp` |
