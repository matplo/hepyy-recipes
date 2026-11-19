"""Audit Linux wheels while retaining sibling native dependency ownership."""
import json
import os
from pathlib import Path
import subprocess
import sys

work, source, target = map(lambda p:Path(p).resolve(),sys.argv[1:])
lock=json.loads(Path(__file__).with_name('packages.lock.json').read_text())['packages']
target.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
env['LD_LIBRARY_PATH']=':'.join(str(work/name/'prefix/lib') for name in lock)
for wheel in sorted(source.glob('*.whl')):
    name=wheel.name.split('-',1)[0].removeprefix('hepyy_')
    command=['auditwheel','repair','--plat','manylinux_2_28_x86_64','-w',str(target)]
    for dep in lock[name]['dependencies']:
        manifest=json.loads((work/dep/'prefix/manifest.json').read_text())
        for filename in manifest['library_files'].values():
            command+=['--exclude',filename]
    subprocess.run([*command,str(wheel)],env=env,check=True)
