"""Validate the exact JEWEL wheels before they enter the PyPI job."""

from email import message_from_bytes
import json
from pathlib import Path
import shutil
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {
    "manylinux_2_28_x86_64": "libjewel_generator.so",
    "macosx_11_0_arm64": "libjewel_generator.dylib",
    "macosx_11_0_x86_64": "libjewel_generator.dylib",
}


def validate(artifacts):
    lock = json.loads((ROOT / "jewel-cpp/wheels.lock.json").read_text())
    native = json.loads((ROOT / "wheels/packages.lock.json").read_text())["packages"]
    dependencies = {name: native[name] for name in ("lhapdf", "pythia8")}
    version = lock["wheel_version"]
    source_url = f"Corresponding source, https://github.com/matplo/jewel-cpp/tree/{lock['source_revision']}"
    wheels = sorted(artifacts.rglob("*.whl"))
    assert len(wheels) == len(PLATFORMS), wheels
    seen = set()
    for wheel in wheels:
        name, wheel_version, python_tag, abi_tag, platform_tag = wheel.stem.split("-")
        assert (name, wheel_version, python_tag, abi_tag) == ("hepyy_jewel_cpp", version, "py3", "none"), wheel
        platform, = set(platform_tag.split(".")) & PLATFORMS.keys()
        assert platform not in seen, wheel
        seen.add(platform)
        with zipfile.ZipFile(wheel) as archive:
            metadata = message_from_bytes(archive.read(f"{name}-{version}.dist-info/METADATA"))
            assert metadata["Name"] == "hepyy-jewel-cpp" and metadata["Version"] == version, wheel
            assert source_url in metadata.get_all("Project-URL"), wheel
            assert set(metadata.get_all("Requires-Dist")) == {
                f"hepyy-{package}=={record['wheel_version']}"
                for package, record in dependencies.items()
            }, wheel
            manifest = json.loads(archive.read(f"{name}/manifest.json"))
            assert manifest["requires_native"] == {
                package: record["abi"] for package, record in dependencies.items()
            }, wheel
            notebook = json.loads(archive.read(
                f"{name}/share/jewel-cpp/examples/jewel_fastjet.ipynb"
            ))
            setup = "".join(notebook["cells"][0]["source"])
            assert "pip install 'hepyy[hepbundle,jewel-cpp]'" in setup, wheel
            libraries = [p for p in archive.namelist()
                         if ".so" in Path(p).name or p.endswith(".dylib")]
            assert libraries == [f"{name}/lib/{PLATFORMS[platform]}"], (wheel, libraries)
    return wheels


if __name__ == "__main__":
    artifacts, dist = map(Path, sys.argv[1:])
    validated = validate(artifacts)
    dist.mkdir()
    for wheel in validated:
        shutil.copy2(wheel, dist)
