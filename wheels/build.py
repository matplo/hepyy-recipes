#!/usr/bin/env python3
"""Build pip-owned C++ payload wheels. No Python bindings or cppyy are bundled.

Requires Python >=3.12, PyYAML, wheel and a C++ toolchain; Linux also patchelf.
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
import time
import urllib.request

import yaml
from wheel.wheelfile import WheelFile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "wheels/packages.lock.json").read_text())["packages"]
SOURCES = {name: (r["version"], r["url"], r["sha256"]) for name,r in LOCK.items()}
FASTJET_ABI = LOCK["fastjet"]["abi"]


def archive_name(url):
    from urllib.parse import urlsplit, parse_qs
    parts = urlsplit(url)
    name = parse_qs(parts.query).get("f", [Path(parts.path).name])[0]
    if Path(name).name != name:
        raise RuntimeError("Unsafe archive name")
    return name


def run(args, cwd=None, env=None):
    print("+", shlex.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def capture(args):
    return subprocess.check_output(list(map(str, args)), text=True)


def library_identity(path):
    if sys.platform == "darwin":
        return Path(capture(["otool", "-D", path]).splitlines()[-1].strip()).name
    return capture(["patchelf", "--print-soname", path]).strip() or path.name


def shared_libraries(prefix):
    return [p for p in (prefix / "lib").iterdir()
            if p.is_file() and not p.is_symlink()
            and (p.name.endswith(".dylib") or ".so" in p.name)]


def extract(name, cache, build):
    version, url, digest = SOURCES[name]
    archive = cache / archive_name(url)
    if not archive.exists():
        # Upstream research servers occasionally time out from hosted runners.
        # Retry transport failures, never checksum mismatches or partial caches.
        request = urllib.request.Request(url, headers={"User-Agent": "hepyy-native-wheels/1"})
        for attempt in range(5):
            print(f"Downloading {url} (attempt {attempt + 1}/5)", flush=True)
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    data = response.read()
                break
            except OSError:
                if attempt == 4:
                    raise
                time.sleep(attempt + 1)
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError(f"Source checksum mismatch: {url}")
        temporary = archive.with_suffix(archive.suffix + ".part")
        temporary.write_bytes(data)
        temporary.replace(archive)
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


def relocate(prefix, dependencies=None):
    dependencies = dependencies or {}
    libraries = shared_libraries(prefix)
    for lib in libraries:
        # Modify each target once, before dereferencing links into the wheel.
        if lib.is_symlink():
            continue
        if sys.platform == "darwin":
            identity = lib.name if lib.name.endswith('.so') else f"@rpath/{lib.name}"
            run(["install_name_tool", "-id", identity, lib])
            for line in capture(["otool", "-L", lib]).splitlines()[1:]:
                old = line.strip().split(" (", 1)[0]
                base = Path(old).name
                if old == identity:
                    continue  # otool -L includes this library's own install ID
                if old.startswith(str(prefix)) or (old.startswith('@rpath/') and (prefix / 'lib' / base).exists()):
                    new = f"@loader_path/{base}"
                else:
                    owner = next((name for name,path in dependencies.items()
                                  if old.startswith(str(path)) or (path / 'lib' / base).exists()), None)
                    if owner:
                        new = f"@loader_path/../../hepyy_{owner}/lib/{base}"
                    elif old.startswith(("/usr/lib/", "/System/Library/", "@loader_path/")):
                        continue
                    else:
                        raise RuntimeError(f"Unapproved external library {old} in {lib}")
                run(["install_name_tool", "-change", old, new, lib])
            # install_name_tool invalidates signatures on Apple silicon.
            run(["codesign", "--force", "--sign", "-", lib])
        else:
            paths = "$ORIGIN"
            for name in dependencies:
                paths += f":$ORIGIN/../../hepyy_{name}/lib"
            run(["patchelf", "--set-rpath", paths, lib])


def build(name, args):
    version, url, digest = SOURCES[name]
    profile = Path(__file__).read_bytes() + Path(__file__).with_name('lhapdf_python.py').read_bytes()
    if LOCK[name].get('builder_sha256') != hashlib.sha256(profile).hexdigest():
        raise RuntimeError('Build profile changed: run upgrade.py sync --write first')
    dest = args.work / name
    if dest.exists():
        raise RuntimeError(f"Build directory already exists; choose a fresh --work: {dest}")
    dest.mkdir(parents=True)
    source = extract(name, args.cache, dest)
    prefix = dest / "prefix"
    prefix.mkdir()
    env = os.environ.copy()
    env['PATH'] = str(Path(sys.executable).parent) + os.pathsep + env.get('PATH','')
    env['PYTHON'] = sys.executable
    # No native installer may target the interpreter's global site-packages.
    env['LHAPDF_PYTHONPATH'] = str(prefix / 'python')
    cxx = env.get("CXX", "c++")
    env["CXXFLAGS"] = "-O2 -fPIC -std=c++17" + (" -D_GLIBCXX_USE_CXX11_ABI=1" if sys.platform == "linux" else "")
    if sys.platform == "darwin":
        env.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
    dependencies = dict(args.dependency_prefix or [])
    if args.fastjet_prefix:
        dependencies['fastjet'] = args.fastjet_prefix
    expected = LOCK[name]
    for dep, abi in expected['requires_native'].items():
        path = dependencies.get(dep)
        if path is None or json.loads((path / 'manifest.json').read_text()).get('abi') != abi:
            raise RuntimeError(f"{name} requires locked {dep} ABI {abi}")
    fastjet = dependencies.get('fastjet')
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
    elif name == 'lhapdf':
        run(['./configure', f'--prefix={prefix}', '--enable-shared', '--disable-static', '--disable-python', 'PYTHON='], source, env)
        run(['make', f'-j{args.jobs}'], source, env)
        run(['make', 'install'], source, env)
    elif name == 'hepmc3':
        run(['cmake','-S',source,'-B',source/'_build', f'-DCMAKE_INSTALL_PREFIX={prefix}',
             '-DCMAKE_INSTALL_LIBDIR=lib','-DCMAKE_CXX_STANDARD=17',f'-DCMAKE_CXX_FLAGS={env["CXXFLAGS"]}',
             '-DHEPMC3_ENABLE_PYTHON=OFF','-DHEPMC3_ENABLE_ROOTIO=OFF','-DHEPMC3_ENABLE_SEARCH=OFF',
             '-DHEPMC3_BUILD_STATIC_LIBS=OFF','-DHEPMC3_INSTALL_EXAMPLES=OFF'],env=env)
        run(['cmake','--build',source/'_build','--parallel',str(args.jobs)],env=env)
        run(['cmake','--install',source/'_build'],env=env)
    else:
        flags = [f'--with-{flag}={dependencies[dep]}' for dep,flag in
                 [('fastjet','fastjet3'),('hepmc3','hepmc3'),('lhapdf','lhapdf6')]]
        run(["./configure", f"--prefix={prefix}", f"--cxx={cxx}",
             f"--cxx-common={env['CXXFLAGS']}", *flags], source, env)
        # Link the HepMC plugin explicitly on both platforms (upstream uses
        # the macOS-only dynamic_lookup shortcut for this target).
        makefile = source / 'Makefile'
        makefile.write_text(makefile.read_text().replace('$(CXX_SONAME)$(notdir $@) -Wl,-undefined,dynamic_lookup',
            '$(CXX_SONAME)$(notdir $@) $(HEPMC3_LIB) -lHepMC3 -Llib -lpythia8'))
        run(["make", f"-j{args.jobs}"], source, env)
        run(["make", "install"], source, env)
    relocate(prefix, dependencies)
    if name == 'lhapdf':
        from lhapdf_python import build as build_python
        build_python(source, prefix, env)
    recipe = yaml.safe_load((ROOT / name / f"{version}.yaml").read_text())
    cppyy = recipe["cppyy"]
    libraries = cppyy["libraries"]
    if name == "fastjet":
        libraries = ["fastjet", "fastjettools", "fastjetplugins"]
    elif name == "fjcontrib":
        libraries = ["fastjetcontribfragile"]
    elif name == 'pythia8':
        libraries = ['pythia8', 'pythia8lhapdf6', 'pythia8hepmc3']
    manifest = dict(schema_version=1, name=name, version=version,
                    distribution_version=expected["wheel_version"], cppyy_namespace=cppyy["namespace"],
                    headers=cppyy["headers"], libraries=libraries,
                    depends_on=list(expected["dependencies"]),
                    source_url=url, source_sha256=digest,
                    abi=expected["abi"], requires_native=expected["requires_native"],
                    dependencies=expected["dependencies"])
    manifest["library_files"] = {}
    for lib in libraries:
        suffix = ".dylib" if sys.platform == "darwin" else ".so"
        candidate = prefix / 'lib' / f'lib{lib}{suffix}'
        if not candidate.exists():
            candidate = prefix / 'lib' / f'lib{lib}.so'
        manifest["library_files"][lib] = library_identity(candidate)
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
    # Deliver the exact upstream sources and packaging recipe with the binary.
    sources = prefix / "sources"
    sources.mkdir()
    shutil.copy2(args.cache / archive_name(url), sources)
    recipe_dir = sources / name
    recipe_dir.mkdir()
    shutil.copy2(ROOT / name / f"{version}.yaml", recipe_dir)
    shutil.copy2(Path(__file__), sources / "build.py")
    shutil.copy2(Path(__file__).with_name("REBUILD.md"), sources)
    shutil.copy2(Path(__file__).with_name("LICENSE"), sources / "PACKAGING-LICENSE")
    shutil.copy2(ROOT / 'wheels/packages.lock.json', sources)
    shutil.copy2(ROOT / 'wheels/lhapdf_python.py', sources)
    (sources / "provenance.json").write_text(json.dumps({
        "package": name, "source_url": url, "source_sha256": digest,
        "packaging_revision": os.environ.get("GITHUB_SHA", "local"),
        "compiler": capture([cxx, "--version"]),
    }, indent=2) + "\n")
    return package(name, prefix, args.output)


def package(name, prefix, output):
    version = LOCK[name]["wheel_version"]
    module = f"hepyy_{name}"
    plat = sysconfig.get_platform().replace("-", "_").replace(".", "_")
    if sys.platform == "darwin":
        target = os.environ.get("MACOSX_DEPLOYMENT_TARGET", "11.0").replace(".", "_")
        plat = f"macosx_{target}_{platform.machine()}"
    python_tag = 'cp310-abi3' if name == 'lhapdf' else 'py3-none'
    tag = f"{python_tag}-{plat}"
    info = f"{module}-{version}.dist-info"
    wheel = output / f"{module}-{version}-{tag}.whl"
    metadata = (f"Metadata-Version: 2.4\nName: hepyy-{name}\nVersion: {version}\n"
                f"Requires-Python: >={'3.10' if name == 'lhapdf' else '3.9'}\nSummary: Native C++ payload for hepyy/cppyy\n")
    metadata += (
        "Author: hepyy contributors; upstream authors credited in bundled sources\n"
        "Project-URL: Repository, https://github.com/matplo/hepyy-recipes\n"
        "Project-URL: Documentation, https://github.com/matplo/hepyy-recipes/blob/main/wheels/README.md\n"
        "Project-URL: Issues, https://github.com/matplo/hepyy-recipes/issues\n"
        "Description-Content-Type: text/markdown\n"
        "License: See bundled upstream COPYING/LICENSE notices; individual fjcontrib components retain their own terms.\n"
    )
    notices = [p for p in sorted((prefix / "licenses").rglob("*")) if p.is_file()]
    for notice in notices:
        metadata += f"License-File: upstream/{notice.relative_to(prefix / 'licenses').as_posix()}\n"
    for dep, dep_version in LOCK[name]['dependencies'].items():
        metadata += f"Requires-Dist: hepyy-{dep}=={dep_version}\n"
    with WheelFile(wheel, "w") as archive:
        archive.writestr(f"{module}/__init__.py", '"""Native data package; load through hepyy.load()."""\n')
        for notice in notices:
            archive.write(notice, f"{info}/licenses/upstream/{notice.relative_to(prefix / 'licenses').as_posix()}")
        if name == 'lhapdf':
            for path in sorted((prefix / 'python/lhapdf').rglob('*')):
                if path.is_file():
                    archive.write(path, 'lhapdf/' + path.relative_to(prefix/'python/lhapdf').as_posix())
            for filename in ('cli.py','upstream_lhapdf.py'):
                archive.write(prefix/filename,f'{module}/{filename}')
            archive.writestr(f'{info}/entry_points.txt','[console_scripts]\nlhapdf = hepyy_lhapdf.cli:main\n')
        # A wheel has no symlink semantics. Write exactly one file per SONAME,
        # rather than materializing aliases as independently loadable copies.
        for library in sorted(shared_libraries(prefix)):
            archive.write(library, f"{module}/lib/{library_identity(library)}")
        for path in sorted(prefix.rglob("*")):
            rel = path.relative_to(prefix)
            if not path.is_file() or rel.parts[0] not in ("include", "share", "licenses", "sources", "manifest.json"):
                continue
            if path.suffix in (".a", ".la") or "pkgconfig" in rel.parts:
                continue
            archive.write(path, f"{module}/{rel.as_posix()}")
        description = (
            f"# hepyy-{name} {version}\n\n"
            f"Native {name} libraries and headers for the shared hepyy/cppyy loader.\n\n"
            "Install hepyy with its matching native extras, then use `hepyy.load()`. "
            "These wheels contain no cppyy runtime or independent Python bindings. "
            "On macOS use an activated conda-forge cppyy environment.\n\n"
            "Tested: Linux x86_64 with pip cppyy (Python 3.10/3.12), and macOS "
            "arm64/x86_64 with conda-forge cppyy (Python 3.12). "
            "Windows and Linux arm64 are not covered.\n\n"
            "The `sources` directory contains the exact upstream source archive, "
            "packaging script, recipe and rebuild instructions. Original license "
            "notices are retained in the payload and distribution metadata.\n"
        )
        archive.writestr(f"{info}/METADATA", metadata + "\n" + description)
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
    parser.add_argument("--dependency-prefix", action='append', type=lambda x: (x.split('=',1)[0],Path(x.split('=',1)[1]).resolve()))
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
