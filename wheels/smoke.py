"""Scientific checks against installed wheels, in a fresh process and registry."""
import argparse
import math
from importlib import metadata
from pathlib import Path
import ctypes
import re
import sys


def check_single_fastjet():
    if sys.platform == 'darwin':
        dyld = ctypes.CDLL(None)
        dyld._dyld_image_count.restype = ctypes.c_uint32
        dyld._dyld_get_image_name.argtypes = [ctypes.c_uint32]
        dyld._dyld_get_image_name.restype = ctypes.c_char_p
        paths = {dyld._dyld_get_image_name(i).decode() for i in range(dyld._dyld_image_count())}
    else:
        paths = {line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines()}
    for name in ('fastjet', 'fastjettools', 'fastjetplugins'):
        matches = {p for p in paths if re.match(r'lib' + name + r'\.', Path(p).name)}
        assert len(matches) == 1, (name, matches)
    print('PASS: exactly one loaded image per FastJet library', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fastjet-only', action='store_true')
    args = parser.parse_args()
    import hepyy
    hepyy.load('fastjet')  # Also exercises hepyy's conda runtime preparation.
    import cppyy
    from hepyy.native import wheel_record

    cppyy.cppdef('''
        #include <vector>
        #include <string>
        int hepyy_stl_probe() { return std::vector<int>{42}[0]; }
    ''')
    assert cppyy.gbl.hepyy_stl_probe() == 42
    hepyy.load('fastjet')
    import fastjet as fj
    assert fj.PseudoJet is cppyy.gbl.fastjet.PseudoJet
    assert wheel_record('fastjet')['provider'] == 'wheel'
    cppyy.cppdef('''
        #include <fastjet/PseudoJet.hh>
        double hepyy_shared_pt(const fastjet::PseudoJet& j) { return j.pt(); }
        std::string hepyy_shared_string(const fastjet::JetDefinition& d) {
            return d.description();
        }
    ''')
    particles = cppyy.gbl.std.vector[fj.PseudoJet]()
    for values in [(40., 0., 0., 40.), (20., 2., 0., math.sqrt(404.)), (-10., 0., 0., 10.)]:
        particles.push_back(fj.PseudoJet(*values))
    definition = fj.JetDefinition(fj.antikt_algorithm, 0.4)
    assert 'anti-kt' in str(cppyy.gbl.hepyy_shared_string(definition))
    sequence = fj.ClusterSequence(particles, definition)
    jets = fj.sorted_by_pt(sequence.inclusive_jets())
    assert len(jets) == 2
    assert math.isclose(jets[0].px(), 60.) and math.isclose(jets[0].py(), 2.)
    assert math.isclose(cppyy.gbl.hepyy_shared_pt(jets[0]), math.sqrt(3604.))
    assert math.isclose(sum(j.E() for j in jets), sum(p.E() for p in particles))
    assert len(jets[0].constituents()) == 2
    print('PASS: STL JIT, shared C++ types/std::string, FastJet clustering and conservation', flush=True)
    check_single_fastjet()
    if args.fastjet_only:
        return

    hepyy.load('fjcontrib')
    import fjcontrib as contrib
    assert contrib.SoftDrop is cppyy.gbl.fastjet.contrib.SoftDrop
    softdrop = contrib.SoftDrop(0., 0.1, 1.)
    groomed = softdrop.result(jets[0])
    assert math.isclose(groomed.pt(), jets[0].pt())
    tau1 = contrib.Nsubjettiness(1, contrib.OnePass_KT_Axes(), contrib.UnnormalizedMeasure(1.))
    tau2 = contrib.Nsubjettiness(2, contrib.OnePass_KT_Axes(), contrib.UnnormalizedMeasure(1.))
    assert tau1.result(jets[0]) > 0
    assert abs(tau2.result(jets[0])) < 1e-8
    # A C++ function consumes the actual proxy returned by a different package.
    assert math.isclose(cppyy.gbl.hepyy_shared_pt(groomed), groomed.pt())
    root = Path(wheel_record('fjcontrib')['lib_dir'])
    assert not any(p.name.startswith(('libfastjet.', 'libfastjettools.')) for p in root.iterdir())
    print('PASS: SoftDrop, Nsubjettiness, shared FastJet identity; no bundled second FastJet', flush=True)
    check_single_fastjet()

    hepyy.load('pythia8')
    import pythia8
    pythia = pythia8.Pythia()
    for setting in ['Beams:eCM = 200.', 'HardQCD:all = on', 'PhaseSpace:pTHatMin = 20.',
                    'Random:setSeed = on', 'Random:seed = 12345',
                    'Next:numberShowInfo = 0', 'Next:numberShowProcess = 0', 'Next:numberShowEvent = 0']:
        assert pythia.readString(setting), setting
    assert pythia.init(), 'Pythia initialization / XML data failed'
    generated = 0
    for _ in range(30):
        if not pythia.next():
            continue
        particles.clear()
        for i in range(pythia.event.size()):
            part = pythia.event[i]
            if part.isFinal():
                particles.push_back(fj.PseudoJet(part.px(), part.py(), part.pz(), part.e()))
        sequence = fj.ClusterSequence(particles, definition)
        jets = fj.sorted_by_pt(sequence.inclusive_jets(5.))
        assert len(jets) > 0
        assert math.isfinite(softdrop.result(jets[0]).pt())
        assert math.isfinite(tau1.result(jets[0]))
        generated += 1
        if generated == 3:
            break
    assert generated == 3
    print('PASS: 3 seeded Pythia events -> FastJet -> SoftDrop / Nsubjettiness', flush=True)
    print('cppyy:', metadata.version('cppyy'), cppyy.__file__, flush=True)


if __name__ == '__main__':
    main()
