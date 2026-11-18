import importlib.util
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('wheel_build', Path(__file__).parents[1] / 'build.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def archive_bytes(name='source/hello.txt'):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:gz') as archive:
        entry = tarfile.TarInfo(name)
        entry.size = 2
        archive.addfile(entry, io.BytesIO(b'ok'))
    return stream.getvalue()


class SourcesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        self.build = self.root / 'build'
        self.build.mkdir()

    def source(self, data):
        return patch.dict(builder.SOURCES, {'test': ('1', 'https://example.invalid/source.tar.gz',
                                                    hashlib.sha256(data).hexdigest())})

    def test_transport_retry_then_checksum_verified_extract(self):
        data = archive_bytes()
        with self.source(data), patch.object(builder.urllib.request, 'urlopen',
                side_effect=[TimeoutError(), io.BytesIO(data)]) as download, patch.object(builder.time, 'sleep'):
            path = builder.extract('test', self.cache, self.build)
        self.assertEqual(download.call_count, 2)
        self.assertEqual((path / 'hello.txt').read_text(), 'ok')
        self.assertFalse(list(self.cache.glob('*.part')))

    def test_bad_download_never_enters_cache(self):
        with self.source(b'expected'), patch.object(builder.urllib.request, 'urlopen', return_value=io.BytesIO(b'bad')):
            with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                builder.extract('test', self.cache, self.build)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_bad_cached_source_fails_without_network(self):
        (self.cache / 'source.tar.gz').write_bytes(b'bad')
        with self.source(b'expected'), patch.object(builder.urllib.request, 'urlopen') as download:
            with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                builder.extract('test', self.cache, self.build)
            download.assert_not_called()

    def test_archive_cannot_escape_build_directory(self):
        data = archive_bytes('../../escape')
        (self.cache / 'source.tar.gz').write_bytes(data)
        with self.source(data), self.assertRaisesRegex(RuntimeError, 'Unsafe'):
            builder.extract('test', self.cache, self.build)
        self.assertFalse((self.root / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
