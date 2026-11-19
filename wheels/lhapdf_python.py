"""Package upstream LHAPDF's Cython API and CLI against its one native library."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import sysconfig

CYTHON_VERSION = '3.3.1'


def build(source, prefix, env):
    import Cython
    if Cython.__version__ != CYTHON_VERSION:
        raise RuntimeError(f'Build needs Cython=={CYTHON_VERSION}, found {Cython.__version__}')
    wrappers=source/'wrappers/python'
    generated=wrappers/'lhapdf_abi3.cpp'
    subprocess.run([sys.executable,'-m','cython','--cplus','-2','-I',str(wrappers),
                    '--module-name','lhapdf.lhapdf',str(wrappers/'lhapdf.pyx'),'-o',str(generated)],check=True,env=env)
    # Upstream's source-tree-relative includes are replaced by installed headers.
    generated.write_text(generated.read_text().replace('../../include/',''))
    target=prefix/'python/lhapdf';target.mkdir(parents=True,exist_ok=True)
    extension=target/'lhapdf.abi3.so'
    import shlex
    command=[env.get('CXX','c++'),'-shared','-fPIC','-O2','-std=c++17',
             '-DCYTHON_LIMITED_API=0x030a0000','-DPy_LIMITED_API=0x030a0000',
             '-I'+sysconfig.get_path('include'),'-I'+str(prefix/'include'),str(generated),
             '-L'+str(prefix/'lib'),'-lLHAPDF','-o',str(extension)]
    if sys.platform=='darwin':
        command+=['-undefined','dynamic_lookup']
    else:
        command+=['-D_GLIBCXX_USE_CXX11_ABI=1','-Wl,-rpath,$ORIGIN/../hepyy_lhapdf/lib']
    subprocess.run(command,check=True,env=env)
    if sys.platform=='darwin':
        deps=subprocess.check_output(['otool','-L',str(extension)],text=True)
        for line in deps.splitlines()[1:]:
            old=line.strip().split(' (',1)[0]
            if Path(old).name.startswith('libLHAPDF'):
                subprocess.run(['install_name_tool','-change',old,
                                '@loader_path/../hepyy_lhapdf/lib/'+Path(old).name,str(extension)],check=True)
        subprocess.run(['codesign','--force','--sign','-',str(extension)],check=True)
    bootstrap='''# Locate pip-owned data before importing the upstream extension.
import os as _os
from pathlib import Path as _Path
_data = str(_Path(__file__).resolve().parent.parent / 'hepyy_lhapdf/share/LHAPDF')
_paths = [p for p in _os.environ.get('LHAPDF_DATA_PATH', '').split(':') if p]
if _data not in _paths:
    _paths.append(_data)
_os.environ['LHAPDF_DATA_PATH'] = ':'.join(_paths)
del _os, _Path, _data, _paths
'''
    (target/'__init__.py').write_text(bootstrap+(wrappers/'__init__.py').read_text())
    # Keep upstream's command/API. Use HTTPS for its default data source.
    (prefix/'upstream_lhapdf.py').write_text((source/'bin/lhapdf').read_text().replace(
        'http://lhapdfsets.web.cern.ch/lhapdfsets/current/', 'https://lhapdfsets.web.cern.ch/current/').replace(
        'self.mainargs.SOURCES[3:] + self.mainargs.SOURCES[:3]', 'self.mainargs.SOURCES[2:] + self.mainargs.SOURCES[:2]'))
    (prefix/'cli.py').write_text('''"""Run the upstream LHAPDF data-management command."""
from pathlib import Path
import runpy

def main():
    runpy.run_path(str(Path(__file__).with_name('upstream_lhapdf.py')), run_name='__main__')
''')
