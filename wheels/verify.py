"""Validate wheel contents, metadata and the single-FastJet ownership contract."""
import json
import sys
import zipfile
from pathlib import Path


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        manifests = [n for n in names if n.endswith('/manifest.json')]
        assert len(manifests) == 1, manifests
        manifest = json.loads(archive.read(manifests[0]))
        prefix = manifests[0].split('/')[0]
        info = next(n for n in names if n.endswith('.dist-info/WHEEL'))
        wheel = archive.read(info).decode()
        assert 'Root-Is-Purelib: false' in wheel
        assert 'Tag: py3-none-' in wheel and 'none-any' not in wheel
        metadata = archive.read(info.replace('/WHEEL', '/METADATA')).decode()
        assert 'Requires-Dist: cppyy' not in metadata
        assert not any('cppyy_backend' in n or 'libCling' in n for n in names)
        assert any(n.startswith(prefix + '/licenses/') for n in names)
        for header in manifest['headers']:
            assert f'{prefix}/include/{header}' in names, header
        for lib in manifest['libraries']:
            assert f'{prefix}/lib/{manifest["library_files"][lib]}' in names, lib
        if manifest['name'] == 'fjcontrib':
            assert 'Requires-Dist: hepyy-fastjet==3.5.1.0' in metadata
            assert not any(Path(n).name.startswith(('libfastjet.', 'libfastjettools.', 'libfastjetplugins.')) for n in names)
        if manifest['name'] == 'pythia8':
            assert f'{prefix}/share/Pythia8/xmldoc/Index.xml' in names
    print('PASS wheel:', path)


if __name__ == '__main__':
    for path in sys.argv[1:]:
        verify(path)
