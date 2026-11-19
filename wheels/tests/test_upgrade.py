import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import yaml

spec=importlib.util.spec_from_file_location('upgrade',Path(__file__).parents[1]/'upgrade.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)


class UpgradeTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.cache=self.root/'cache';self.cache.mkdir()
        (self.root/'hepbundle').mkdir();(self.root/'wheels').mkdir()
        (self.root/'wheels/build.py').write_text('# reviewed build profile')
        (self.root/'hepbundle/main.yaml').write_text('depends_on: [fastjet, fjcontrib, pythia8]\n')
        for n,v in [('fastjet','3.5.1'),('fjcontrib','1.102'),('hepmc3','3.3.1'),('lhapdf','6.5.5'),('pythia8','8.317')]:
            self.recipe(n,v)

    def recipe(self,name,version,flags=None):
        p=self.root/name;p.mkdir(exist_ok=True)
        (p/f'{version}.yaml').write_text(yaml.safe_dump(dict(name=name,version=version,
            url=f'https://example.invalid/{name}-{{version}}.tar.gz',configure_args=flags or [])))
        (self.cache/f'{name}-{version}.tar.gz').write_bytes(b'upstream source')

    def test_noop_and_highest_numeric_version(self):
        self.recipe('fastjet','3.9.0');self.recipe('fastjet','3.10.0')
        first=u.resolve(self.root,self.cache,{})
        self.assertEqual(first['packages']['fastjet']['version'],'3.10.0')
        self.assertEqual(first,u.resolve(self.root,self.cache,first['packages']))

    def test_dependency_upgrade_rebuilds_consumers(self):
        old=u.resolve(self.root,self.cache,{})
        self.recipe('fastjet','3.5.3')
        new=u.resolve(self.root,self.cache,old['packages'])
        self.assertEqual(new['packages']['fastjet']['wheel_version'],'3.5.3.0')
        self.assertEqual(new['packages']['fjcontrib']['wheel_version'],'1.102.1')
        self.assertEqual(new['packages']['pythia8']['wheel_version'],'8.317.1')
        self.assertEqual(new['packages']['lhapdf']['wheel_version'],'6.5.5.1')

    def test_same_version_recipe_change_requires_new_revision(self):
        old=u.resolve(self.root,self.cache,{})
        self.recipe('lhapdf','6.5.5',['--new-build-flag'])
        new=u.resolve(self.root,self.cache,old['packages'])
        self.assertEqual(new['packages']['lhapdf']['wheel_version'],'6.5.5.1')
        self.assertEqual(new['packages']['pythia8']['dependencies']['lhapdf'],'6.5.5.1')

    def test_never_reuses_an_index_version_for_changed_inputs(self):
        old=u.resolve(self.root,self.cache,{})
        self.recipe('fastjet','3.5.3')
        with patch.object(u,'index_versions',return_value={'3.5.3.0':[], '3.5.3.1':[]}):
            new=u.resolve(self.root,self.cache,old['packages'],'https://index.invalid')
        self.assertEqual(new['packages']['fastjet']['wheel_version'],'3.5.3.2')

    def test_rejects_unknown_build_profile(self):
        (self.root/'hepbundle/main.yaml').write_text('depends_on: [unreviewed]\n')
        with self.assertRaisesRegex(ValueError,'No reviewed native build profile'):
            u.resolve(self.root,self.cache,{})

    def test_query_archive_and_unsafe_paths(self):
        self.assertEqual(u.archive_name('https://x.invalid/downloads/?f=LHAPDF-6.5.5.tar.gz'),'LHAPDF-6.5.5.tar.gz')
        with self.assertRaises(ValueError):u.archive_name('https://x.invalid/?f=../escape.tar.gz')

    def test_recipe_checksum_mismatch_is_fatal(self):
        p=self.root/'fastjet/3.5.1.yaml';data=yaml.safe_load(p.read_text())
        data['native_wheel']={'sha256':'wrong'};p.write_text(yaml.safe_dump(data))
        with self.assertRaisesRegex(ValueError,'checksum mismatch'):
            u.resolve(self.root,self.cache,{})

if __name__=='__main__':unittest.main()
