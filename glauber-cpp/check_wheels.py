"""Validate the tested Glauber CLI wheel set before promotion."""

from email import message_from_bytes
import json
from pathlib import Path
import shutil
import sys
import zipfile


VERSION = json.loads(Path(__file__).with_name("wheels.lock.json").read_text())["wheel_version"]
PLATFORMS = {"manylinux_2_28_x86_64", "macosx_11_0_arm64", "macosx_11_0_x86_64"}


def validate(artifacts):
    wheels = sorted(artifacts.rglob("*.whl"))
    assert len(wheels) == len(PLATFORMS), wheels
    seen = set()
    for wheel in wheels:
        name, version, python_tag, abi_tag, platform_tag = wheel.stem.split("-")
        assert (name, version, python_tag, abi_tag) == ("hepyy_glauber_cpp", VERSION, "py3", "none"), wheel
        platform, = set(platform_tag.split(".")) & PLATFORMS
        assert platform not in seen, wheel
        seen.add(platform)
        with zipfile.ZipFile(wheel) as archive:
            base = f"{name}-{version}"
            metadata = message_from_bytes(archive.read(f"{base}.dist-info/METADATA"))
            assert metadata["Name"] == "hepyy-glauber-cpp" and metadata["Version"] == version
            assert not metadata.get_all("Requires-Dist")
            entry = archive.getinfo(f"{base}.data/scripts/glauber-pbpb")
            assert entry.external_attr >> 16 & 0o111, wheel
            with archive.open(entry) as binary:
                magic = binary.read(4)
            expected = b"\x7fELF" if platform.startswith("manylinux") else b"\xcf\xfa\xed\xfe"
            assert magic == expected, (wheel, magic)
    return wheels


if __name__ == "__main__":
    artifacts, dist = map(Path, sys.argv[1:])
    validated = validate(artifacts)
    dist.mkdir()
    for wheel in validated:
        shutil.copy2(wheel, dist)
