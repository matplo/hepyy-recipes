#!/usr/bin/env python3
"""Build pip-owned C++ payload wheels. No Python bindings or cppyy are bundled.

Requires Python >=3.10, PyYAML, wheel and a C++ toolchain; Linux also patchelf.
Run in a manylinux container for portable Linux artifacts. See README.md.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys
import sysconfig
import tarfile
import urllib.request

import yaml
from wheel.wheelfile import WheelFile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "fastjet": ("3.5.1", "https://fastjet.fr/repo/fastjet-3.5.1.tar.gz",
                "9a4154163e72041dee3fdde9cb24e814625e178091a8734a6ad5375e5371b423"),
    "fjcontrib": ("1.102", "https://fastjet.hepforge.org/contrib/downloads/fjcontrib-1.102.tar.gz",
                  "971bdd6260a0755acadcdd04c2e22aece81625038f8aab869b8c472ed2091b7e"),
    "pythia8": ("8.317", "https://pythia.org/releases/pythia83/pythia8317.tgz",
                "1ae551d14dac495ddfe6b344792035ebe410fe6c6004d44a335e0ece0e745adf"),
}
FASTJET_ABI = "fastjet-3.5.1.0-cxx17-v1"


def run(args, cwd=None, env=None):
    print("+", shlex.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def capture(args):
    return subprocess.check_output(list(map(str, args)), text=True)


def extract(name, cache, build):
    version, url, digest = SOURCES[name]
    archive = cache / url.rsplit("/", 1)[1]
    if not archive.exists():
        with urllib.request.urlopen(url, timeout=120) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f"Source checksum mismatch: {archive}")
    target = build / "source"
    target.mkdir()
    with tarfile.open(archive) as tar:
        # Native source tarballs are data, never allowed to escape the build dir.
        for member in tar.getmembers():
            resolved = (target / member.name).resolve()
            if not resolved.is_relative_to(target.resolve()) or member.issym() or member.islnk():
                raise RuntimeError(f"Unsafe source archive member: {member.name}")
        tar.extractall(target, filter="data")
    children = list(target.iterdir())
    if len(children) != 1 or not children[0].is_dir():
        raise RuntimeError("Expected a single upstream source directory")
    return children[0]


def relocate(prefix, fastjet=None):
    libraries = [p for p in (prefix / "lib").iterdir()
                 if p.is_file() and (p.name.endswith(".dylib") or ".so" in p.name)]
    for lib in libraries:
        # Modify each target once, before dereferencing links into the wheel.
        if lib.is_symlink():
            continue
        if sys.platform == "darwin":
            run(["install_name_tool", "-id", f"@rpath/{lib.name}", lib])
            for line in capture(["otool", "-L", lib]).splitlines()[1:]:
                old = line.strip().split(" (", 1)[0]
                base = Path(old).name
                if old == f"@rpath/{lib.name}":
                    continue  # otool -L includes this library's own install ID
                if old.startswith(str(prefix)):
                    new = f"@loader_path/{base}"
                elif fastjet and (old.startswith(str(fastjet)) or base.startswith(("libfastjet.", "libfastjettools.", "libfastjetplugins."))):
                    new = f"@loader_path/../../hepyy_fastjet/lib/{base}"
                elif old.startswith(("/usr/lib/", "/System/Library/", "@loader_path/")) or old == f"@rpath/{lib.name}":
                    continue
                else:
                    raise RuntimeError(f"Unapproved external library {old} in {lib}")
                run(["install_name_tool", "-change", old, new, lib])
            # install_name_tool invalidates signatures on Apple silicon.
            run(["codesign", "--force", "--sign", "-", lib])
        else:
            paths = "$ORIGIN"
            if fastjet:
                paths += ":$ORIGIN/../../hepyy_fastjet/lib"
            run(["patchelf", "--set-rpath", paths, lib])


def build(name, args):
    version, url, digest = SOURCES[name]
    dest = args.work / name
    if dest.exists():
        raise RuntimeError(f"Build directory already exists; choose a fresh --work: {dest}")
    dest.mkdir(parents=True)
    source = extract(name, args.cache, dest)
    prefix = dest / "prefix"
    prefix.mkdir()
    env = os.environ.copy()
    cxx = env.get("CXX", "c++")
    env["CXXFLAGS"] = "-O2 -fPIC -std=c++17" + (" -D_GLIBCXX_USE_CXX11_ABI=1" if sys.platform == "linux" else "")
    if sys.platform == "darwin":
        env.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
    fastjet = args.fastjet_prefix
    if name == "fastjet":
        run(["./configure", f"--prefix={prefix}", "--enable-shared", "--disable-static",
             "--enable-allcxxplugins", "--disable-auto-ptr"], source, env)
        run(["make", f"-j{args.jobs}"], source, env)
        run(["make", "install"], source, env)
    elif name == "fjcontrib":
        if not fastjet:
            raise RuntimeError("fjcontrib requires --fastjet-prefix from this wheel build")
        manifest = json.loads((fastjet / "manifest.json").read_text())
        if manifest.get("abi") != FASTJET_ABI:
            raise RuntimeError("FastJet ABI mismatch")
        run(["./configure", f"--prefix={prefix}", f"--fastjet-config={fastjet / 'bin/fastjet-config'}",
             f"CXX={cxx}", f"CXXFLAGS={env['CXXFLAGS']}"], source, env)
        # Upstream lowercase version files shadow the C++ <version> header.
        for path in source.glob("*/version"):
            path.rename(path.with_suffix(".txt"))
        run(["make", f"-j{args.jobs}"], source, env)
        run(["make", "install"], source, env)
        run(["make", "fragile-shared"], source, env)
        run(["make", "fragile-shared-install"], source, env)
    else:
        run(["./configure", f"--prefix={prefix}", f"--cxx={cxx}",
             f"--cxx-common={env['CXXFLAGS']}"], source, env)
        run(["make", f"-j{args.jobs}"], source, env)
        run(["make", "install"], source, env)
    relocate(prefix, fastjet if name == "fjcontrib" else None)
    recipe = yaml.safe_load((ROOT / name / f"{version}.yaml").read_text())
    cppyy = recipe["cppyy"]
    libraries = cppyy["libraries"]
    if name == "fastjet":
        libraries = ["fastjet", "fastjettools", "fastjetplugins"]
    elif name == "fjcontrib":
        libraries = ["fastjetcontribfragile"]
    manifest = dict(schema_version=1, name=name, version=version,
                    distribution_version=f"{version}.0", cppyy_namespace=cppyy["namespace"],
                    headers=cppyy["headers"], libraries=libraries,
                    depends_on=recipe.get("depends_on", []),
                    source_url=url, source_sha256=digest,
                    abi=FASTJET_ABI if name == "fastjet" else f"{name}-{version}.0-cxx17-v1",
                    requires_native={"fastjet": FASTJET_ABI} if name == "fjcontrib" else {})
    (prefix / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Preserve original license notices alongside native payloads.
    licenses = prefix / "licenses"
    licenses.mkdir()
    for path in source.rglob("*"):
        if path.is_file() and path.name.upper().startswith(("COPYING", "LICENSE")):
            target = licenses / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    if not any(licenses.rglob("*")):
        raise RuntimeError("No upstream license found")
    return package(name, prefix, args.output)


def package(name, prefix, output):
    version = SOURCES[name][0] + ".0"
    module = f"hepyy_{name}"
    plat = sysconfig.get_platform().replace("-", "_").replace(".", "_")
    if sys.platform == "darwin":
        target = os.environ.get("MACOSX_DEPLOYMENT_TARGET", "11.0").replace(".", "_")
        plat = f"macosx_{target}_{platform.machine()}"
    tag = f"py3-none-{plat}"
    info = f"{module}-{version}.dist-info"
    wheel = output / f"{module}-{version}-{tag}.whl"
    metadata = (f"Metadata-Version: 2.1\nName: hepyy-{name}\nVersion: {version}\n"
                "Requires-Python: >=3.9\nSummary: Native C++ payload for hepyy/cppyy\n")
    if name == "fjcontrib":
        metadata += "Requires-Dist: hepyy-fastjet==3.5.1.0\n"
    with WheelFile(wheel, "w") as archive:
        archive.writestr(f"{module}/__init__.py", '"""Native data package; load through hepyy.load()."""\n')
        for path in sorted(prefix.rglob("*")):
            rel = path.relative_to(prefix)
            if not path.is_file() or rel.parts[0] not in ("include", "lib", "share", "licenses", "manifest.json"):
                continue
            if path.suffix in (".a", ".la") or "pkgconfig" in rel.parts:
                continue
            archive.write(path, f"{module}/{rel.as_posix()}")
        archive.writestr(f"{info}/METADATA", metadata + "\n")
        archive.writestr(f"{info}/WHEEL", f"Wheel-Version: 1.0\nGenerator: hepyy-native\nRoot-Is-Purelib: false\nTag: {tag}\n")
    print(wheel, flush=True)
    return wheel


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=SOURCES)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fastjet-prefix", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if sys.platform not in ("darwin", "linux"):
        parser.error("Only Linux and macOS are supported")
    for key in ("work", "cache", "output", "fastjet_prefix"):
        value = getattr(args, key)
        if value is not None:
            value = value.resolve()
            setattr(args, key, value)
            if key != "fastjet_prefix":
                value.mkdir(parents=True, exist_ok=True)
    build(args.package, args)


if __name__ == "__main__":
    main()
