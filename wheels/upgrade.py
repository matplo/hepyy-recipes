#!/usr/bin/env python3
"""Explicit recipe-to-wheel synchronization and protected artifact promotion.

sync --write prepares a reviewable lock and optional paired hepyy metadata.
build compiles the locked dependency graph. status compares it with an index.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from packaging.version import Version, InvalidVersion
import yaml

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'wheels/packages.lock.json'
SUPPORTED = {'fastjet', 'fjcontrib', 'hepmc3', 'lhapdf', 'pythia8'}
DEPS = {'fjcontrib': ['fastjet'], 'pythia8': ['fastjet', 'hepmc3', 'lhapdf']}


def archive_name(url):
    parts = urllib.parse.urlsplit(url)
    name = urllib.parse.parse_qs(parts.query).get('f', [Path(parts.path).name])[0]
    if name != Path(name).name or not name.endswith(('.tgz', '.tar.gz')):
        raise ValueError(f'Unsafe/unsupported archive filename: {name}')
    return name


def latest_recipe(root, name):
    candidates = []
    for path in (root / name).glob('*.yaml'):
        try:
            version = Version(path.stem)
        except InvalidVersion:
            continue
        if not version.is_prerelease:
            candidates.append((version, path))
    if not candidates:
        raise ValueError(f'No stable recipe for {name}')
    return max(candidates)[1]


def index_versions(name, index):
    try:
        with urllib.request.urlopen(f'{index.rstrip("/")}/pypi/hepyy-{name}/json', timeout=45) as r:
            return json.load(r)['releases']
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {}
        raise


def resolve(root, cache, previous, index=None):
    bundle = yaml.safe_load((root / 'hepbundle/main.yaml').read_text())
    names = [entry.split('/')[0] for entry in bundle['depends_on']]
    ordered = []
    visiting = set()
    def visit(name):
        if name not in SUPPORTED:
            raise ValueError(f'No reviewed native build profile for {name}')
        if name in ordered:
            return
        if name in visiting:
            raise ValueError('Dependency cycle')
        visiting.add(name)
        for dep in DEPS.get(name, []):
            visit(dep)
        ordered.append(name)
        visiting.remove(name)
    for name in names:
        visit(name)
    result = {}
    builder = (root / 'wheels/build.py').read_bytes()
    helper = root / 'wheels/lhapdf_python.py'
    if helper.exists():
        builder += helper.read_bytes()
    # A changed recipe produces a new, coherent bundle cohort. Give unchanged
    # upstream releases fresh packaging revisions too: publishing rebuilt bytes
    # under an old PyPI filename would violate index immutability.
    cohort = bytearray(builder)
    cohort.extend(json.dumps(DEPS,sort_keys=True).encode())
    for package in ordered:
        path = latest_recipe(root, package)
        data = yaml.safe_load(path.read_text())
        cohort.extend(package.encode() + path.read_bytes())
        script = path.parent / data.get('build_script','__no_script__')
        if script.is_file():
            cohort.extend(script.read_bytes())
    bundle_inputs = hashlib.sha256(cohort).hexdigest()
    bundle_changed = set(previous) != set(ordered) or any(
        previous.get(package,{}).get('bundle_inputs') != bundle_inputs for package in ordered)
    for name in ordered:
        path = latest_recipe(root, name)
        recipe = yaml.safe_load(path.read_text())
        version = str(recipe['version'])
        if version != path.stem or recipe['name'] != name:
            raise ValueError(f'Recipe identity mismatch: {path}')
        url = recipe['url'].format(version=version, version_nodot=version.replace('.', ''),
                                   version_major=version.split('.')[0], version_minor=version.split('.')[1])
        filename = archive_name(url)
        cached = cache / filename
        if not cached.exists():
            # Use the same bounded transport retry policy as the native builder.
            import time
            for attempt in range(5):
                try:
                    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'hepyy-wheel-upgrade/1'}), timeout=45) as r:
                        data = r.read()
                    break
                except OSError:
                    if attempt == 4:
                        raise
                    time.sleep(attempt + 1)
            cached.write_bytes(data)
        digest = hashlib.sha256(cached.read_bytes()).hexdigest()
        expected = recipe.get('native_wheel', {}).get('sha256')
        if expected and expected != digest:
            raise ValueError(f'Recipe source checksum mismatch: {name}')
        script = path.parent / recipe.get('build_script', '__no_script__')
        recipe_digest = hashlib.sha256(path.read_bytes() + (script.read_bytes() if script.is_file() else b'')).hexdigest()
        deps = {dep: result[dep]['abi'] for dep in DEPS.get(name, [])}
        signature = hashlib.sha256(json.dumps([version,url,digest,recipe_digest,deps,hashlib.sha256(builder).hexdigest()]).encode()).hexdigest()
        old = previous.get(name, {})
        revision = 0
        if old.get('version') == version:
            revision = int(old['wheel_version'].rsplit('.',1)[1])
            if bundle_changed or old.get('signature') != signature:
                revision += 1
        wheel_version = f'{version}.{revision}'
        if index and (bundle_changed or old.get('signature') != signature):
            published = index_versions(name, index)
            while wheel_version in published:
                revision += 1
                wheel_version = f'{version}.{revision}'
        result[name] = dict(version=version, wheel_version=wheel_version, url=url,
                            archive=filename, sha256=digest, recipe=str(path.relative_to(root)),
                            recipe_sha256=recipe_digest, signature=signature,
                            builder_sha256=hashlib.sha256(builder).hexdigest(), bundle_inputs=bundle_inputs,
                            abi=f'{name}-{wheel_version}-cxx17-v1', requires_native=deps,
                            dependencies={dep:result[dep]['wheel_version'] for dep in deps})
    return {'schema_version':1, 'bundle':'hepbundle', 'packages':result}


def sync_hepyy(root, lock):
    records = lock['packages']
    p = root / 'pyproject.toml'
    text = p.read_text()
    for name, rec in records.items():
        line = f'{name} = ["hepyy-{name}=={rec["wheel_version"]}"]'
        if re.search(r'^'+re.escape(name)+r' = ', text, re.M):
            text = re.sub(r'^'+re.escape(name)+r' = .*$', lambda _:line, text, flags=re.M)
        else:
            text = text.replace('[project.optional-dependencies]\n','[project.optional-dependencies]\n'+line+'\n')
        recipe = ROOT / rec['recipe']
        target = root / 'src/hepyy/recipes' / name
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(recipe, target / recipe.name)
        data = yaml.safe_load(recipe.read_text())
        script = data.get('build_script')
        if script and '\n' not in script and (recipe.parent / script).is_file():
            shutil.copyfile(recipe.parent / script, target / script)
    deps = ', '.join(f'"hepyy-{n}=={r["wheel_version"]}"' for n,r in records.items())
    line = f'hepbundle = [{deps}]'
    if re.search(r'^hepbundle = ', text, re.M):
        text = re.sub(r'^hepbundle = .*$',lambda _:line,text,flags=re.M)
    else:
        text = text.replace('[project.optional-dependencies]\n','[project.optional-dependencies]\n'+line+'\n')
    p.write_text(text)
    (root / 'tools/native-packages.lock.json').write_text(json.dumps(lock,indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sync = sub.add_parser('sync')
    sync.add_argument('--cache', type=Path, required=True)
    sync.add_argument('--write', action='store_true')
    sync.add_argument('--hepyy-root', type=Path)
    sync.add_argument('--index', default=None, help='Optional index root for immutable-version collision avoidance')
    run = sub.add_parser('run', help='Sync recipes, build in dependency order and validate wheels; never upload')
    run.add_argument('--hepyy-root', type=Path, required=True)
    run.add_argument('--index', default='https://pypi.org')
    build = sub.add_parser('build')
    for arg in ('work','cache','output'):
        for command in (build,run):
            command.add_argument('--'+arg, type=Path, required=True)
    build.add_argument('--jobs', type=int, default=4)
    run.add_argument('--jobs', type=int, default=4)
    promote=sub.add_parser('promote', help='Dispatch tested main artifacts to a protected publishing workflow')
    promote.add_argument('--run-id',type=int,required=True)
    promote.add_argument('--index',choices=('testpypi','pypi'),required=True)
    sub.add_parser('requirements')
    status = sub.add_parser('status')
    status.add_argument('--index', default='https://pypi.org')
    args = parser.parse_args()
    if args.command == 'promote':
        subprocess.run(['gh','workflow','run','publish-native.yml','--repo','matplo/hepyy-recipes','--ref','main',
                        '-f',f'run_id={args.run_id}','-f',f'destination={args.index}'],check=True)
        return
    if args.command == 'run':
        subprocess.run([sys.executable,__file__,'sync','--write','--cache',str(args.cache),
                        '--hepyy-root',str(args.hepyy_root),'--index',args.index],check=True)
    old = json.loads(LOCK.read_text()) if LOCK.exists() else {'packages':{}}
    if args.command == 'sync':
        args.cache.mkdir(parents=True,exist_ok=True)
        if args.hepyy_root and not (args.hepyy_root/'pyproject.toml').is_file():
            raise ValueError('--hepyy-root must be an existing hepyy checkout')
        new = resolve(ROOT,args.cache,old['packages'],args.index)
        for name, rec in new['packages'].items():
            prior = old['packages'].get(name,{}).get('wheel_version','not locked')
            print(f'{name}: {prior} -> {rec["wheel_version"]}; sha256={rec["sha256"]}')
        if args.write:
            LOCK.write_text(json.dumps(new,indent=2)+'\n')
            bundle_path = ROOT/'hepbundle/main.yaml'
            bundle_text = bundle_path.read_text()
            for package,record in new['packages'].items():
                bundle_text = re.sub(r'(?m)^(  - '+re.escape(package)+r')/[^\s]+',lambda m:m[1]+'/'+record['version'],bundle_text)
            bundle_path.write_text(bundle_text)
            if args.hepyy_root:
                sync_hepyy(args.hepyy_root.resolve(),new)
        elif args.hepyy_root:
            print('Preview only: add --write to update paired hepyy metadata')
    elif args.command == 'requirements':
        for name,rec in old['packages'].items():
            print(f'hepyy-{name}=={rec["wheel_version"]}')
    elif args.command == 'status':
        for name, rec in old['packages'].items():
            present = rec['wheel_version'] in index_versions(name,args.index)
            print(f'{name}=={rec["wheel_version"]}: {"published" if present else "not published"}')
    else:
        prefixes = {}
        for name, rec in old['packages'].items():
            command = [sys.executable,str(ROOT/'wheels/build.py'),name,'--work',str(args.work),
                       '--cache',str(args.cache),'--output',str(args.output),'--jobs',str(args.jobs)]
            if name == 'fjcontrib':
                command += ['--fastjet-prefix',str(prefixes['fastjet'])]
            for dep in rec['dependencies']:
                command += ['--dependency-prefix',f'{dep}={prefixes[dep]}']
            subprocess.run(command,check=True)
            prefixes[name] = (args.work/name/'prefix').resolve()
        if args.command == 'run':
            wheels = sorted(args.output.glob('*.whl'))
            subprocess.run([sys.executable,str(ROOT/'wheels/verify.py'),*map(str,wheels)],check=True)
            subprocess.run([sys.executable,'-m','twine','check','--strict',*map(str,wheels)],check=True)
            for wheel in wheels:
                if '-abi3-' in wheel.name:
                    subprocess.run([sys.executable,'-m','abi3audit','--strict',str(wheel)],check=True)


if __name__ == '__main__':
    main()
