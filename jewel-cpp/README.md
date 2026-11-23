# JEWEL C++ wheel releases

The JEWEL wheel builder and example tests live in the public jewel-cpp
repository. This repository pins the source and hepyy revisions in
`wheels.lock.json` and runs the `JEWEL native wheels` workflow. The workflow
builds Linux x86_64 and macOS arm64 and Intel wheels. It tests the installed
script and notebook in clean environments and verifies that they use the
hepbundle libraries.

The shared `publish-native.yml` workflow promotes the three wheels from a
successful JEWEL build on the same recipes commit. Supply the build run ID,
choose `package_set=jewel-cpp` and `destination=pypi`, and use
`verify_only=true` for a dry run. Uploading requires review in the
`pypi-jewel-cpp` GitHub environment.

| PyPI Trusted Publisher field | Value |
|---|---|
| Project name | `hepyy-jewel-cpp` |
| Owner | `matplo` |
| Repository | `hepyy-recipes` |
| Workflow name | `publish-native.yml` |
| Environment name | `pypi-jewel-cpp` |
