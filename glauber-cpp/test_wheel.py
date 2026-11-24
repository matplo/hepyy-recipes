"""Test the installed Glauber CLI and verify JEWEL can consume its event table."""

import csv
from importlib.metadata import distribution
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import sysconfig
import tempfile


VERSION = json.loads(Path(__file__).with_name("wheels.lock.json").read_text())["wheel_version"]


def generate(cli, work):
    sample = work / "pbpb"
    subprocess.run([str(cli), str(sample), "6000", "72913"], check=True)
    metadata = json.loads((sample / "metadata.json").read_text())
    with (sample / "events.csv").open() as stream:
        rows = list(csv.DictReader(stream))
    with (sample / "centrality.csv").open() as stream:
        bins = list(csv.DictReader(stream))
    assert metadata["trials"] == 6000 and metadata["sigma_nn_inelastic_mb"] == 67.6
    assert len(rows) == metadata["inelastic_events"] and len(bins) == 20
    assert all(math.isclose(float(row["taa_mb_inverse"]), int(row["ncoll"]) / 67.6,
                            rel_tol=1e-10) for row in rows)
    return sample / "events.csv", [row for row in rows if int(row["centrality_high_pct"]) <= 10]


def test_jewel(source, work, table, central):
    packages = Path(sysconfig.get_path("purelib"))
    build = work / "jewel-build"
    subprocess.run([
        "cmake", "-S", str(source), "-B", str(build),
        "-DBUILD_TESTING=OFF", "-DCMAKE_BUILD_TYPE=Release",
        "-DJEWEL_WITH_PYTHIA8=ON",
        f"-DJEWEL_PYTHIA8_ROOT={packages / 'hepyy_pythia8'}",
        f"-DJEWEL_LHAPDF_ROOT={packages / 'hepyy_lhapdf'}",
    ], check=True)
    subprocess.run(["cmake", "--build", str(build), "--target", "jewel-run-events", "--parallel", "4"], check=True)
    output = work / "jewel.jsonl"
    env = os.environ.copy()
    env.pop("PYTHIA8DATA", None)
    subprocess.run([
        str(build / "jewel-run-events"), str(output), "16", "2601017", "medium",
        "--ecm", "5020", "--pt-min", "40", "--pt-max", "100", "--isr-only",
        "--centrality", "0", "10", "--glauber-events", str(table),
        "--table-energy", "jewel", "--longitudinal-boost", "on", "--jewel-fragmentation",
        "--subtraction-radius", "0.4", "--geometry-step", "0.02",
    ], cwd=work, env=env, check=True)
    with output.open() as stream:
        header = json.loads(next(stream))
        records = [json.loads(line) for line in stream]
    assert header["centrality_percent"] == [0, 10]
    glauber = header["glauber"]
    assert glauber["sampling"] == "ncoll-proportional"
    assert glauber["minimum_bias_events"] == len(central)
    mean = math.fsum(float(row["taa_mb_inverse"]) for row in central) / len(central)
    assert math.isclose(glauber["taa_mb_inverse"], mean, rel_tol=1e-12)
    support = {float(row["b_fm"]) for row in central}
    events = [event for event in records if event["type"] == "event"]
    assert records[-1]["type"] == "summary" and records[-1]["accepted"] == len(events) > 0
    assert all(event["impact_parameter_fm"] in support and len(event["geometry"]) == 2
               and event["subtracted_particles"] for event in events)
    print(f"JEWEL accepted {len(events)}/16 events, using {len(central)} central Glauber rows.")


def main():
    dist = distribution("hepyy-glauber-cpp")
    assert dist.version == VERSION and not dist.requires
    cli = Path(shutil.which("glauber-pbpb")).resolve()
    assert cli.is_relative_to(Path(sys.prefix).resolve())
    source = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="glauber-wheel-") as temp:
        work = Path(temp)
        table, central = generate(cli, work)
        test_jewel(source, work, table, central)


if __name__ == "__main__":
    main()
