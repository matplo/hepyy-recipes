# First public native-wheel release

Prepared distributions: hepyy-fastjet 3.5.1.0, hepyy-fjcontrib 1.102.0,
hepyy-pythia8 8.317.0, then hepyy 0.2.31. The pre-change hepyy tag
`pre-pip-wheels-2026-11-18` must never be moved.

## Account setup (owner action)

In matplo/hepyy-recipes create GitHub environments `testpypi` and `pypi`.
Configure required reviewer approval and allow deployments from `main` only.
Do this before dispatching the publishing workflow; an automatically created
unprotected environment does not supply a human approval gate.

For **each** of the three native project names, add a pending Trusted Publisher
on both TestPyPI and PyPI using these exact values:

| Field | Value |
|---|---|
| Owner | matplo |
| Repository | hepyy-recipes |
| Workflow filename | publish-native.yml |
| Environment | testpypi on TestPyPI; pypi on PyPI |

Pending publishers do not reserve names. Confirm ownership/name availability
again before the first upload. No API token needs to be shared with an agent.
Existing hepyy publishing uses repository `matplo/hepyy`, workflow `publish.yml`
and environment `pypi`; verify its existing Trusted Publisher and reviewers.

## Review and rehearsal

1. Review/merge the paired hepyy and recipes PRs. Neither merge publishes.
   The native workflow pins the reviewed hepyy candidate commit; update the pin
   if the loader changes. The final hepyy `v*` tag is reserved for step 7.
2. Run/await Native wheels CI on the exact recipes `main` commit to release.
   All jobs must pass. Sources, licenses, strict metadata and scientific tests
   are checked before artifacts are accepted.
3. Dispatch **Publish tested native wheels** from `main`, supplying that numeric
   run ID and destination `testpypi`. Review checksums and approve the `testpypi`
   environment. The workflow accepts only a successful main-push CI run at the
   exact publishing commit, with all nine native wheels.
4. In fresh Linux and activated macOS conda cppyy environments, install ordinary
   dependencies from PyPI/conda first. Download the three native projects from
   TestPyPI using `pip download --index-url https://test.pypi.org/simple/ --no-deps
   --only-binary=:all: hepyy-fastjet==3.5.1.0 hepyy-fjcontrib==1.102.0
   hepyy-pythia8==8.317.0`. Install these local files and the hepyy 0.2.31 candidate
   wheel with `--no-deps`, then run `wheels/smoke.py` with an empty registry.
   Do not combine indexes with extra-index-url. Record the run and results.
5. Obtain explicit public-publication approval for the exact native versions
   and checksums. Dispatch the same workflow/run ID to `pypi`, then approve its
   protected environment. The workflow publishes the tested native artifact set.
   A partial upload is recoverable by inspecting PyPI and preparing a deliberate
   retry; automatic skip-existing is disabled to expose unexpected collisions.
6. Verify public native installs and run the scientific checks before releasing
   hepyy. The hepyy release workflow also requires all pinned native versions and
   platform artifacts to exist on PyPI.
7. Obtain approval for the hepyy release, then create a new `v0.2.31` tag on the
   reviewed hepyy release commit. Its existing workflow publishes wheel/sdist.
   Verify public `pip install 'hepyy[cppyy,fjcontrib,pythia8]'` on Linux, and
   `pip install 'hepyy[fjcontrib,pythia8]'` with activated macOS conda cppyy.

No index upload, environment change, merge or release tag is performed merely
by preparing these files. TestPyPI and public PyPI use separate accounts and
publisher configuration. Wheels include exact corresponding upstream sources,
packaging code, rebuild instructions and original component license notices.
Release reviewers should inspect those materials before public distribution.

## Supported first release

Linux x86_64 (tested Ubuntu 24.04, pip cppyy 3.5.0, Python 3.10/3.12), macOS
arm64 and Intel (activated conda-forge cppyy 3.5.0, Python 3.12). Local arm64
Python 3.14 also passed. Deployment tags are build targets; additional minimum
OS claims need validation. Native wheels intentionally provide no pip source
build fallback. Existing heyy source builds remain available.
