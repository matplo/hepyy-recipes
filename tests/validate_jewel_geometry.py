#!/usr/bin/env python3
"""Build and exercise the geometry recipe against a caller-supplied JEWEL source.

Requires Jinja2, gfortran, a built LHAPDF with CT14nlo, and optionally existing
JEWEL integration tables computed for the cards below. All generation/building
happens in a new work directory; the supplied source and installation are read-only.
"""

import argparse
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

import jinja2


RECIPE = Path(__file__).resolve().parents[1] / "jewel/2.6.0-custom.sh"
TABLES = ("splitint.dat", "pdfs.dat", "xsecs.dat")
MEDIUM = "TI 0.45\nTAUI 0.7\nCENTRMIN 8.7667742646\nCENTRMAX 8.7667742646\n"
CARD = """NEVENT {events}
NJOB {seed}
LOGFILE jewel.log
HEPMCFILE events.hepmc
SPLITINTFILE splitint.dat
PDFFILE pdfs.dat
XSECFILE xsecs.dat
MEDIUMPARAMS medium.dat
SQRTS 5020.0
PTMIN 50.0
PTMAX 400.0
ETAMAX 3.1
PDFSET 13100
WEIGHTED {weighted}
ISOCHANNEL {isospin}
KEEPRECOILS {recoils}
WRITESCATCEN {recoils}
WRITEDUMMIES {recoils}
SHORTHEPMC {short}
"""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_case(work, prefix, env, name, medium, *, enabled, step=0.02,
             perf=False, recoils=False, short=True, weighted=False, isospin="PP", seed=None):
    directory = work / name
    directory.mkdir()
    for table in TABLES:
        candidate = work / "tables" / table
        if candidate.exists():
            (directory / table).symlink_to(candidate)
    card = CARD.format(events=8 if isospin == "XX" else 1 if medium == "simple" else 3,
                       seed=seed if seed is not None else 902 if medium == "simple" else 901,
                       weighted="T" if weighted else "F", isospin=isospin,
                       recoils="T" if recoils else "F", short="T" if short else "F")
    (directory / "params.dat").write_text(card)
    (directory / "medium.dat").write_text(MEDIUM)
    child_env = dict(env)
    for key in ("JEWEL_GEOMETRY_FILE", "JEWEL_GEOMETRY_RUN_ID", "JEWEL_GEOMETRY_STEP_FM"):
        child_env.pop(key, None)
    if enabled:
        child_env.update(JEWEL_GEOMETRY_FILE="events.hepmc.geometry.csv",
                         JEWEL_GEOMETRY_RUN_ID=name, JEWEL_GEOMETRY_STEP_FM=str(step))
    binary = prefix / "bin" / f"jewel-2.6.0-custom{'-perf' if perf else ''}-{medium}"
    print(f"Running {name}", flush=True)
    with (directory / "stdout.log").open("w") as log:
        subprocess.run([binary, "params.dat"], cwd=directory, env=child_env,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    # The first run may generate tables. Subsequent runs read identical copies.
    for table in TABLES:
        if not (work / "tables" / table).exists():
            shutil.copy2(directory / table, work / "tables" / table)
    return directory


def check_rows(directory, medium):
    hepmc = directory / "events.hepmc"
    event_ids = [int(line.split()[1]) for line in hepmc.read_text().splitlines() if line.startswith("E ")]
    if not event_ids:
        raise AssertionError(f"no accepted events: {directory}")
    sidecar = directory / "events.hepmc.geometry.csv"
    with sidecar.open() as stream:
        rows = list(csv.DictReader(line for line in stream if not line.startswith("#")))
    assert [(int(row["event_id"]), int(row["leg_id"])) for row in rows] == [
        (event, leg) for event in event_ids for leg in (1, 2)
    ], "sidecar events differ from accepted HepMC events"
    for row in rows:
        for key in ("L_geom_T_fm", "L_hot_fm", "L_hot_T_fm", "int_T3_dl"):
            value = float(row[key])
            assert value >= 0 and value < float("inf"), (key, value)
            if medium == "vac":
                assert value == 0, (key, value)
        assert float(row["L_hot_T_fm"]) <= float(row["L_hot_fm"]) + 1e-10
        assert float(row["L_hot_T_fm"]) <= float(row["L_geom_T_fm"]) + 1e-8
    if medium == "simple":
        assert any(float(row["L_hot_fm"]) > 0 for row in rows), "medium sample has no hot paths"
    return rows, len(event_ids)


def check_refusal_preserves_output(work, prefix, env):
    """Direct invocation must reject a stale sidecar before opening HepMC."""
    directory = work / "refuse-existing"
    shutil.copytree(work / "vac-on", directory, symlinks=True)
    protected = ("events.hepmc", "events.hepmc.geometry.csv")
    before = {name: sha(directory / name) for name in protected}
    child_env = dict(env, JEWEL_GEOMETRY_FILE="events.hepmc.geometry.csv",
                     JEWEL_GEOMETRY_RUN_ID="refuse-existing")
    with (directory / "refusal.log").open("w") as log:
        result = subprocess.run([prefix / "bin/jewel-2.6.0-custom-vac", "params.dat"],
                                cwd=directory, env=child_env, stdout=log,
                                stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode != 0, "existing sidecar was not rejected"
    assert before == {name: sha(directory / name) for name in protected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--lhapdf-prefix", required=True, type=Path)
    parser.add_argument("--tables-dir", type=Path, help="Optional existing tables for the matching card")
    parser.add_argument("--work-dir", type=Path, help="New directory; default is a temporary directory")
    parser.add_argument("--fixtures-dir", type=Path, help="Optional new directory for small reference samples")
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="jewel-geometry-"))
    if args.work_dir:
        work.mkdir(parents=True, exist_ok=False)
    prefix = work / "install"
    source = work / "source"
    shutil.copytree(args.source_dir, source)
    (work / "tables").mkdir()
    if args.tables_dir:
        for table in TABLES:
            shutil.copy2(args.tables_dir / table, work / "tables" / table)
    env = dict(os.environ)
    env["LHAPDF_DATA_PATH"] = str(args.lhapdf_prefix.resolve() / "share/LHAPDF")
    env["LHAPATH"] = env["LHAPDF_DATA_PATH"]
    library_key = "DYLD_LIBRARY_PATH" if platform.system() == "Darwin" else "LD_LIBRARY_PATH"
    env[library_key] = str(args.lhapdf_prefix.resolve() / "lib") + os.pathsep + env.get(library_key, "")
    rendered = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(RECIPE.read_text()).render(
        prefix=str(prefix), version="2.6.0-custom", platform=platform.system().lower(),
        lhapdf_prefix=str(args.lhapdf_prefix.resolve()))
    print(f"Building recipe in {work}; log: {work / 'build.log'}", flush=True)
    with (work / "build.log").open("w") as log:
        subprocess.run(["bash", "-c", rendered], cwd=source, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900)
    report = {"recipe_sha256": sha(RECIPE), "compiler": subprocess.check_output(
        ["gfortran", "--version"], text=True).splitlines()[0], "cases": {}}
    cases = [
        ("vac", "vac", {}), ("simple", "simple", {}),
        ("perf-vac", "vac", {"perf": True}),
        ("perf-simple", "simple", {"perf": True}),
        ("recoils", "simple", {"perf": True, "recoils": True, "weighted": True, "seed": 903}),
        ("long", "simple", {"perf": True, "short": False}),
        ("isospin", "vac", {"perf": True, "isospin": "XX"}),
    ]
    for name, medium, options in cases:
        off = run_case(work, prefix, env, name + "-off", medium, enabled=False, **options)
        on = run_case(work, prefix, env, name + "-on", medium, enabled=True, **options)
        for artifact in ("events.hepmc", "out.ran"):
            assert (off / artifact).read_bytes() == (on / artifact).read_bytes(), f"{name}: changed {artifact}"
        rows, count = check_rows(on, medium)
        report["cases"][name] = {"events": count, "hepmc_sha256": sha(on / "events.hepmc"),
                                  "rng_sha256": sha(on / "out.ran"), "unchanged": True}
        if name in ("vac", "simple", "recoils", "long") and args.fixtures_dir:
            fixture = args.fixtures_dir / name
            fixture.mkdir(parents=True, exist_ok=False)
            for artifact in ("params.dat", "medium.dat", "events.hepmc.geometry.csv"):
                shutil.copy2(on / artifact, fixture / artifact)
            (fixture / "events.hepmc.gz").write_bytes(gzip.compress((on / "events.hepmc").read_bytes(), mtime=0))
    # Re-evaluate identical axes at half the maximum time step.
    fine = run_case(work, prefix, env, "simple-fine", "simple", enabled=True, step=0.01)
    fine_rows, _ = check_rows(fine, "simple")
    base_rows, _ = check_rows(work / "simple-on", "simple")
    assert sha(fine / "events.hepmc") == sha(work / "simple-on/events.hepmc")
    length_error = max(abs(float(a["L_hot_fm"]) - float(b["L_hot_fm"]))
                       for a, b in zip(base_rows, fine_rows))
    assert length_error <= 0.05, f"path integration did not converge: {length_error} fm"
    report["step_halving_max_L_hot_difference_fm"] = length_error
    check_refusal_preserves_output(work, prefix, env)
    report["existing_sidecar_preserves_hepmc"] = True
    (work / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.fixtures_dir:
        (args.fixtures_dir / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
