"""Analytic tests of the actual Fortran estimator embedded in the JEWEL recipe.

Run with python -m unittest discover -s tests. No JEWEL tarball/PDF data needed.
"""

import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


RECIPE = Path(__file__).resolve().parents[1] / "jewel/2.6.0-custom.sh"
DRIVER = """
program test_geometry
  implicit none
  real(8) :: x,y,b,r,tmax,p(4),step,lg,lh,lht,it3
  integer :: mode
  common/testmedium/mode
  read(*,*) x,y,b,r,tmax,p,step,mode
  call jg_lengths(x,y,b,r,tmax,p,step,lg,lh,lht,it3)
  write(*,'(4ES25.16)') lg,lh,lht,it3
end program

real(8) function gettemp(x,y,z,t)
  implicit none
  real(8) :: x,y,z,t
  integer :: mode
  common/testmedium/mode
  gettemp=0.5d0
  if(mode.eq.1)then
    gettemp=0.d0
    if(t.ge.1.d0.and.t.lt.4.d0) gettemp=1.d0
  elseif(mode.eq.2)then
    gettemp=0.d0
    if(t.ge.1.d0.and.t.lt.4.d0) gettemp=t
  endif
end function

subroutine jg_fail(message)
  use iso_fortran_env, only: error_unit
  implicit none
  character(*) :: message
  write(error_unit,*) message
  stop 1
end subroutine
"""


@unittest.skipUnless(shutil.which("gfortran"), "gfortran is required")
class GeometryEstimatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="jewel-geometry-unit-")
        work = Path(cls.temp.name)
        patch = RECIPE.read_text().split("cat > custom-geometry.patch <<'PATCH_EOF'\n", 1)[1].split("\nPATCH_EOF", 1)[0]
        additions = "\n".join(line[1:] for line in patch.splitlines()
                              if line.startswith("+") and not line.startswith("+++"))
        helper = re.search(r"      SUBROUTINE JG_LENGTHS\(.*?(?=      SUBROUTINE JG_CLOSE)",
                           additions, re.DOTALL).group()
        (work / "lengths.f").write_text(helper)
        (work / "driver.f90").write_text(DRIVER)
        cls.binary = work / "estimator"
        subprocess.run(["gfortran", "-O2", str(work / "lengths.f"), str(work / "driver.f90"),
                        "-o", str(cls.binary)], check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def lengths(self, *, x=0, y=0, b=0, r=5, tmax=100, p=(10, 0, 0, 10), step=.02, mode=0):
        data = " ".join(map(str, (x, y, b, r, tmax, *p, step, mode))) + "\n"
        result = subprocess.run([self.binary], input=data, capture_output=True, text=True, check=True)
        return tuple(map(float, result.stdout.split()))

    def assertValues(self, actual, expected, places=10):
        for value, target in zip(actual, expected):
            self.assertAlmostEqual(value, target, places=places)

    def test_uniform_central_paths(self):
        self.assertValues(self.lengths(), (5, 5, 5, .625))
        self.assertValues(self.lengths(p=(-10, 0, 0, 10)), (5, 5, 5, .625))

    def test_displaced_point_and_intersection_of_nuclei(self):
        self.assertValues(self.lengths(x=1), (4, 4, 4, .5))
        self.assertValues(self.lengths(x=1, p=(-10, 0, 0, 10)), (6, 6, 6, .75))
        self.assertValues(self.lengths(b=4), (3, 3, 3, .375))
        distance = math.sqrt(21)
        self.assertValues(self.lengths(b=4, p=(0, 10, 0, 10)),
                          (distance, distance, distance, distance / 8))

    def test_finite_rapidity_separates_transverse_and_3d_length(self):
        self.assertValues(self.lengths(p=(6, 0, 8, 10)), (5, 5 / .6, 5, 5 / .6 / 8))

    def test_medium_lifetime_limits_exposure_but_not_geometry(self):
        self.assertValues(self.lengths(tmax=2), (5, 2, 2, .25))

    def test_initial_zero_temperature_does_not_terminate_integration(self):
        self.assertValues(self.lengths(r=10, tmax=10, mode=1), (10, 3, 3, 3))

    def test_temperature_integral_converges(self):
        coarse = self.lengths(r=10, tmax=10, step=.04, mode=2)
        fine = self.lengths(r=10, tmax=10, step=.02, mode=2)
        exact = (4**4 - 1**4) / 4
        self.assertLess(abs(fine[3] - exact), abs(coarse[3] - exact) / 3.9)
        self.assertAlmostEqual(fine[3], exact, delta=.002)

    def test_vacuum_and_stationary_leg(self):
        self.assertValues(self.lengths(r=0), (0, 0, 0, 0))
        self.assertValues(self.lengths(p=(0, 0, 0, 10)), (0, 0, 0, 0))


if __name__ == "__main__":
    unittest.main()
