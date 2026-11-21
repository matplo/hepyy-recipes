set -e
# JEWEL 2.6.0 with custom patches, installed next to the stock binaries. Three builds:
#
#   bin/jewel-2.6.0-{simple,vac}              stock JEWEL 2.6.0
#   bin/jewel-2.6.0-custom-{simple,vac}       stock + partons-v1 + geometry-v1 (opt-in)
#   bin/jewel-2.6.0-custom-perf-{simple,vac}  stock + partons-v1 + geometry-v1 + perf-v1
#
# custom and custom-perf generate the same events for the same card and NJOB; custom-perf is
# faster. Keep custom as the reference for checking that.
#
# Patch set version: CUSTOM_PATCHSET below. Change it whenever a patch changes; it is written
# to info/CUSTOM-PATCHES.txt together with the checksums of the stock and patched sources.
#
# partons-v1  (short HepMC output, SHORTHEPMC T, the default)
#   * two particle records with HepMC status 23 after the two beam nucleons: JEWEL's
#     matrix-element partons (LME1, LME2) after PYTHIA's initial-state shower and before the
#     vacuum or medium final-state shower; same definition in -simple and -vac;
#   * PARI(17) (hard-process pT) in the event-scale field of the E line (stock writes 0).
#   Readers that select HepMC status 1, 3 and 4 (Rivet, hepyy-utils) are unaffected.
#   Extra parton records are omitted for EEJJ/PPDY; their short event scale
#   is still set. Neither change applies to the long output.
#
# perf-v1  (speed only; the generated events are unchanged)
#   * medium-simple.f: GETTEMPMAX (the temperature at the centre, a per-event constant) is
#     cached until the impact parameter changes, and NPART(0,0,0,0), the normalisation of the
#     initial energy density, is computed once. Both were recomputed on every scattering step.
#   * jewel-2.6.0.f: a stray "call flush()" in DOCOHSCATTERING, which flushed every open
#     unit on every call, is removed.
#   Checked: stock and patched medium routines give bitwise-identical values with the same
#   random numbers. Expected gain in medium runs roughly 1.5-2x; the -vac binaries only get
#   the flush removal.
# geometry-v1 (opt-in, PPJJ only; no changes to the generated events)
#   JEWEL_GEOMETRY_FILE creates a new CSV sidecar; JEWEL_GEOMETRY_RUN_ID is
#   required. JEWEL_GEOMETRY_STEP_FM controls midpoint integration (0.02 fm).
#   Two rows per accepted HepMC event contain the production point, impact
#   parameter, ME and shower-start momenta, transverse geometric length, hot
#   3D/transverse lengths and integral T^3 dl. See the repository README.
CUSTOM_PATCHSET="partons-v1+geometry-v1+perf-v1"
STOCK_SHA256="78b39f19513c3633c00d45b22f0803c0873a93d98a536d66efc9277255bf5b81"
STOCK_MEDIUM_SHA256="a5f5a16d984cf84d28c2c789f72557a64b85cb6ae51bc9f395b1f2a7f4e2bd38"
STOCK_VAC_SHA256="c83fda6a0b81ce0dc9f524bbf9a3c68f0225f090107a5cd4d6711edad0b20ea0"
GEOMETRY_SHA256="0ff7dab92339212757531de8b73724b9b3a078969454066163371b49ae39d846"
GEOMETRY_MEDIUM_SHA256="2b9058cf87f69b399260f1008438dcfed9c405307f507ef20d7952eb17899bbb"
GEOMETRY_VAC_SHA256="2c68ad776c128e020d6775c6e7d7f7689e92f80756515fc2c3b75e8366db4d18"
PARTONS_SHA256="5ab26243f3512e6a345e6c12dd5d64e0213b5cd1815ad0141bd968142f204761"
PATCHED_SHA256="9f1a71144dcc6dd0aa6eda64e628f418490f1e88347e62e52eec930005cb458a"
PATCHED_MEDIUM_SHA256="1465c089bd94604034e3efa4662afcf1cf93342beab52523b4527cc08c100bd6"

lhapdf_prefix="{{ lhapdf_prefix }}"
if [ -z "$lhapdf_prefix" ]; then
  echo "[jewel] ERROR: lhapdf not found in hepyy registry — install lhapdf first"
  exit 1
fi
{% if platform == "darwin" %}
sed -i '' 's/-lstdc++/-lc++/g' Makefile
{% endif %}

sha256_of () {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# a re-run in a cached source tree may start from the patched sources
check_sha () {  # file expected
  local found; found=$(sha256_of "$1")
  if [ "$found" != "$2" ]; then
    echo "[jewel] ERROR: $1 has sha256 $found, expected $2 ($CUSTOM_PATCHSET)"
    exit 1
  fi
}
for f in jewel-2.6.0.f medium-simple.f medium-vac.f; do
  if [ -f "$f.stock" ]; then cp "$f.stock" "$f"; fi
  cp "$f" "$f.stock"
done
check_sha jewel-2.6.0.f "$STOCK_SHA256"
check_sha medium-simple.f "$STOCK_MEDIUM_SHA256"
check_sha medium-vac.f "$STOCK_VAC_SHA256"

mkdir -p {{ prefix }}/bin {{ prefix }}/settings {{ prefix }}/info

binaries () { for b in jewel-2.6.0-*; do [ -f "$b" ] && [ -x "$b" ] && echo "$b"; done; }

# 1) stock binaries (every jewel-2.6.0-* executable the Makefile builds, as the stock recipe)
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
built=$(binaries)
[ -n "$built" ] || { echo "[jewel] ERROR: make produced no jewel-2.6.0-* binaries"; exit 1; }
cp $built {{ prefix }}/bin/

# 2) patched binaries: partons-v1
cat > custom-partons.patch <<'PATCH_EOF'
--- jewel-2.6.0.f
+++ jewel-2.6.0.f
@@ -1106,6 +1106,10 @@
 ***********************************************************************
 	subroutine genevent(j,b1,b2)
 	implicit none
+C--outgoing hard partons before the final-state shower (HepMC status 23)
+      COMMON/HARDPART/PHARD(2,5),KHARD(2),NHARD
+      DOUBLE PRECISION PHARD
+      INTEGER KHARD,NHARD
 C--identifier of file for hepmc output and logfile
 	common/hepmcid/hpmcfid,logfid
 	integer hpmcfid,logfid
@@ -1237,6 +1241,7 @@
         LTIME=GETLTIMEMAX()
 
  99	  CALL PYEVNT
+      NHARD=0
         NPART=N-OFFSET
         EVWEIGHT=PARI(10)
 	  SUMOFWEIGHTS=SUMOFWEIGHTS+EVWEIGHT
@@ -1267,6 +1272,20 @@
 	  if (k(lme1,1).lt.11) K(LME1,1)=1
 	  if (k(lme2,1).lt.11) K(LME2,1)=1
 	  PID=K(LME1,2)
+C--store the outgoing hard partons before the final-state shower
+      NHARD=2
+      KHARD(1)=K(LME1,2)
+      KHARD(2)=K(LME2,2)
+      PHARD(1,1)=P(LME1,1)
+      PHARD(1,2)=P(LME1,2)
+      PHARD(1,3)=P(LME1,3)
+      PHARD(1,4)=P(LME1,4)
+      PHARD(1,5)=P(LME1,5)
+      PHARD(2,1)=P(LME2,1)
+      PHARD(2,2)=P(LME2,2)
+      PHARD(2,3)=P(LME2,3)
+      PHARD(2,4)=P(LME2,4)
+      PHARD(2,5)=P(LME2,5)
 	  DO 183 IPART=OFFSET+1, OFFSET+NPART
 	   if ((.not.isqorg(k(ipart,2))).and.
      &	   (k(ipart,1).lt.11)) then
@@ -9111,6 +9130,10 @@
 ***********************************************************************
 	SUBROUTINE CONVERTTOHEPMC(J,EVNUM,PID,beam1,beam2)
 	IMPLICIT NONE
+C--outgoing hard partons before the final-state shower (HepMC status 23)
+      COMMON/HARDPART/PHARD(2,5),KHARD(2),NHARD
+      DOUBLE PRECISION PHARD
+      INTEGER KHARD,NHARD
       COMMON/PYJETS/N,NPAD,K(23000,5),P(23000,5),V(23000,5)
 	INTEGER N,NPAD,K
 	DOUBLE PRECISION P,V
@@ -9184,9 +9207,10 @@
  131	  continue
 	  if(writescatcen) NFIRST=NFIRST+nscatcen
 	  if(writedummies) NFIRST=NFIRST+nscatcen
+      IF((NHARD.EQ.2).AND.(COLLIDER.NE.'EEJJ')) NFIRST=NFIRST+2
 
-	  WRITE(J,5000)'E ',EVNUM,-1,0.d0,0.d0,0.d0,0,0,NVERTEX,1,2,0,1,
-     &PARI(10)
+      WRITE(J,5000)'E ',EVNUM,-1,PARI(17),0.d0,0.d0,0,0,NVERTEX,
+     &1,2,0,1,PARI(10)
 	  WRITE(J,'(A2,I2,A5)')'N ',1,'"0"'
 	  WRITE(J,'(A)')'U GEV MM'
 	  WRITE(J,5100)'C ',PARI(1)*1.d9,0.d0
@@ -9224,6 +9248,15 @@
      &	-sqrt(sqrts**2/4.-mneutron**2),sqrts/2.,mneutron,4,0,0,-1,0
 	    endif
 	  ENDIF
+C--write out the outgoing hard partons (status 23)
+      IF((NHARD.EQ.2).AND.(COLLIDER.NE.'EEJJ'))THEN
+        PBARCODE=PBARCODE+1
+        WRITE(J,5500)'P ',PBARCODE,KHARD(1),PHARD(1,1),PHARD(1,2),
+     &  PHARD(1,3),PHARD(1,4),PHARD(1,5),23,0,0,0,0
+        PBARCODE=PBARCODE+1
+        WRITE(J,5500)'P ',PBARCODE,KHARD(2),PHARD(2,1),PHARD(2,2),
+     &  PHARD(2,3),PHARD(2,4),PHARD(2,5),23,0,0,0,0
+      ENDIF
 C--write out scattering centres
 	if(writescatcen) then
 	    do 133 i=1,nscatcen
PATCH_EOF
patch -p0 --forward --dry-run < custom-partons.patch
patch -p0 --forward < custom-partons.patch
check_sha jewel-2.6.0.f "$PARTONS_SHA256"

# geometry-v1 is shared by custom and custom-perf; it is disabled by default.
cat > custom-geometry.patch <<'PATCH_EOF'
--- jewel-2.6.0.f
+++ jewel-2.6.0.f
@@ -241,0 +242 @@
+      CALL JG_CLOSE()
@@ -701,0 +703,2 @@
+C--Validate diagnostics before opening/truncating the HepMC output.
+      CALL JG_INIT(COLLIDER)
@@ -1314,0 +1318,2 @@
+C--Snapshot after kinematic reshuffling, before any cascade evolution.
+      CALL JG_CAPTURE(LME1,LME2,X0,Y0)
@@ -9574,0 +9580,2 @@
+C--Only events that reached HepMC output receive two sidecar rows.
+      CALL JG_WRITE(EVNUM,PARI(10))
@@ -9730,0 +9738,234 @@
+
+C--geometry-v1: opt-in diagnostics. No random draws or event changes.
+      SUBROUTINE JG_INIT(COLLIDER)
+      USE, INTRINSIC :: IEEE_ARITHMETIC, ONLY: IEEE_IS_FINITE
+      IMPLICIT NONE
+      CHARACTER*(*) COLLIDER
+      DOUBLE PRECISION GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME(2,4),GP(2,4)
+      INTEGER GUNIT,GPID(2),GLAST
+      LOGICAL GENABLED,GREADY
+      COMMON/JGREAL/GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME,GP
+      COMMON/JGINT/GUNIT,GPID,GLAST
+      COMMON/JGLOG/GENABLED,GREADY
+      SAVE /JGREAL/,/JGINT/,/JGLOG/
+      CHARACTER*4096 PATH
+      CHARACTER*128 RUNID,STEPSTR
+      CHARACTER*1 CH
+      INTEGER IOS,NLEN,I
+      LOGICAL ALNUM
+
+      GENABLED=.FALSE.
+      GREADY=.FALSE.
+      GLAST=-1
+      CALL GET_ENVIRONMENT_VARIABLE('JEWEL_GEOMETRY_FILE',PATH,
+     &     LENGTH=NLEN,STATUS=IOS)
+      IF(IOS.EQ.1) RETURN
+      IF(IOS.NE.0.OR.NLEN.GT.LEN(PATH))
+     &     CALL JG_FAIL('JEWEL_GEOMETRY_FILE is too long or unreadable')
+      IF(LEN_TRIM(PATH).EQ.0) RETURN
+      IF(COLLIDER.NE.'PPJJ')
+     &     CALL JG_FAIL('geometry-v1 supports COLLIDER PPJJ only')
+      CALL GET_ENVIRONMENT_VARIABLE('JEWEL_GEOMETRY_RUN_ID',RUNID,
+     &     LENGTH=NLEN,STATUS=IOS)
+      IF(IOS.NE.0.OR.NLEN.LT.1.OR.NLEN.GT.LEN(RUNID))
+     &     CALL JG_FAIL('JEWEL_GEOMETRY_RUN_ID is required (max 128)')
+      DO I=1,NLEN
+        CH=RUNID(I:I)
+        ALNUM=(CH.GE.'a'.AND.CH.LE.'z').OR.
+     &        (CH.GE.'A'.AND.CH.LE.'Z').OR.
+     &        (CH.GE.'0'.AND.CH.LE.'9')
+        IF(.NOT.ALNUM)THEN
+          IF(I.EQ.1.OR.INDEX('_.-',CH).EQ.0)
+     &         CALL JG_FAIL('invalid run ID: use letters/digits/_.-')
+        ENDIF
+      ENDDO
+      GSTEP=0.02D0
+      CALL GET_ENVIRONMENT_VARIABLE('JEWEL_GEOMETRY_STEP_FM',STEPSTR,
+     &     LENGTH=NLEN,STATUS=IOS)
+      IF(IOS.NE.1)THEN
+        IF(IOS.NE.0.OR.NLEN.LT.1.OR.NLEN.GT.LEN(STEPSTR))
+     &       CALL JG_FAIL('invalid JEWEL_GEOMETRY_STEP_FM')
+        DO I=1,NLEN
+          IF(INDEX('0123456789.+-eEdD',STEPSTR(I:I)).EQ.0)
+     &         CALL JG_FAIL('JEWEL_GEOMETRY_STEP_FM must be one number')
+        ENDDO
+        READ(STEPSTR,*,IOSTAT=IOS) GSTEP
+        IF(IOS.NE.0) CALL JG_FAIL('invalid JEWEL_GEOMETRY_STEP_FM')
+      ENDIF
+      IF(.NOT.IEEE_IS_FINITE(GSTEP))
+     &     CALL JG_FAIL('JEWEL_GEOMETRY_STEP_FM must be finite')
+      IF(GSTEP.LE.0.D0)
+     &     CALL JG_FAIL('JEWEL_GEOMETRY_STEP_FM must be positive')
+      OPEN(NEWUNIT=GUNIT,FILE=TRIM(PATH),STATUS='NEW',ACTION='WRITE',
+     &     IOSTAT=IOS)
+      IF(IOS.NE.0)
+     &     CALL JG_FAIL('cannot create geometry file (must not exist)')
+      GENABLED=.TRUE.
+      WRITE(GUNIT,'(A)',IOSTAT=IOS) '# schema=jewel_geometry_v1'
+      IF(IOS.NE.0) CALL JG_FAIL('cannot write geometry header')
+      WRITE(GUNIT,'(A)') '# run_id='//TRIM(RUNID)
+      WRITE(GUNIT,'(A)') '# axis=shower_start'
+      WRITE(GUNIT,'(A,ES24.16E3)') '# step_fm=',GSTEP
+      WRITE(GUNIT,'(A)') '# frame=collision_cm; b along x; z along beam'
+      WRITE(GUNIT,'(A)') '# units=GeV,fm,fm/c; int_T3_dl=GeV^3*fm'
+      WRITE(GUNIT,'(A)') '# estimator=straight_ray_midpoint_v1'
+      WRITE(GUNIT,'(A)') '# time_limit=GETLTIMEMAX (generator bound)'
+      CALL JG_MEDHEADER(GUNIT)
+      WRITE(GUNIT,'(A)')
+     & 'event_id,leg_id,pid,weight,b_fm,centrality,'//
+     & 'x0_fm,y0_fm,z0_fm,t0_fm,me_px,me_py,me_pz,me_e,'//
+     & 'px,py,pz,e,L_geom_T_fm,L_hot_fm,L_hot_T_fm,int_T3_dl'
+      FLUSH(GUNIT,IOSTAT=IOS)
+      IF(IOS.NE.0) CALL JG_FAIL('cannot flush geometry header')
+      END
+
+      SUBROUTINE JG_CAPTURE(L1,L2,X0,Y0)
+      IMPLICIT NONE
+      INTEGER L1,L2,L(2),I,J
+      DOUBLE PRECISION X0,Y0
+      COMMON/PYJETS/N,NPAD,K(23000,5),P(23000,5),V(23000,5)
+      INTEGER N,NPAD,K
+      DOUBLE PRECISION P,V
+      COMMON/HARDPART/PHARD(2,5),KHARD(2),NHARD
+      DOUBLE PRECISION PHARD
+      INTEGER KHARD,NHARD
+      DOUBLE PRECISION GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME(2,4),GP(2,4)
+      INTEGER GUNIT,GPID(2),GLAST
+      LOGICAL GENABLED,GREADY
+      COMMON/JGREAL/GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME,GP
+      COMMON/JGINT/GUNIT,GPID,GLAST
+      COMMON/JGLOG/GENABLED,GREADY
+      SAVE /JGREAL/,/JGINT/,/JGLOG/
+      IF(.NOT.GENABLED) RETURN
+      IF(NHARD.NE.2) CALL JG_FAIL('missing two hard partons')
+      L(1)=L1
+      L(2)=L2
+      GX0=X0
+      GY0=Y0
+      CALL JG_MEDSTATE(GB,GC,GR,GTMAX)
+      DO I=1,2
+        GPID(I)=KHARD(I)
+        DO J=1,4
+          GME(I,J)=PHARD(I,J)
+          GP(I,J)=P(L(I),J)
+        ENDDO
+      ENDDO
+      GREADY=.TRUE.
+      END
+
+      SUBROUTINE JG_WRITE(EVNUM,WEIGHT)
+      IMPLICIT NONE
+      INTEGER EVNUM,I,J,IOS
+      DOUBLE PRECISION WEIGHT,LG,LH,LHT,IT3,P4(4)
+      DOUBLE PRECISION GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME(2,4),GP(2,4)
+      INTEGER GUNIT,GPID(2),GLAST
+      LOGICAL GENABLED,GREADY
+      COMMON/JGREAL/GSTEP,GX0,GY0,GB,GC,GR,GTMAX,GME,GP
+      COMMON/JGINT/GUNIT,GPID,GLAST
+      COMMON/JGLOG/GENABLED,GREADY
+      SAVE /JGREAL/,/JGINT/,/JGLOG/
+      IF(.NOT.GENABLED) RETURN
+      IF(.NOT.GREADY) CALL JG_FAIL('event has no geometry snapshot')
+      IF(EVNUM.LE.GLAST) CALL JG_FAIL('non-increasing HepMC event ID')
+      DO I=1,2
+        DO J=1,4
+          P4(J)=GP(I,J)
+        ENDDO
+        CALL JG_LENGTHS(GX0,GY0,GB,GR,GTMAX,P4,GSTEP,LG,LH,LHT,IT3)
+        WRITE(GUNIT,100,IOSTAT=IOS) EVNUM,I,GPID(I),WEIGHT,GB,GC,
+     &       GX0,GY0,0.D0,0.D0,(GME(I,J),J=1,4),(GP(I,J),J=1,4),
+     &       LG,LH,LHT,IT3
+        IF(IOS.NE.0) CALL JG_FAIL('cannot write geometry row')
+      ENDDO
+      FLUSH(GUNIT,IOSTAT=IOS)
+      IF(IOS.NE.0) CALL JG_FAIL('cannot flush geometry rows')
+      GLAST=EVNUM
+      GREADY=.FALSE.
+ 100  FORMAT(I0,',',I0,',',I0,19(',',ES24.16E3))
+      END
+
+      SUBROUTINE JG_LENGTHS(X0,Y0,B,R,TMAX,P4,STEP,LG,LH,LHT,IT3)
+      USE, INTRINSIC :: IEEE_ARITHMETIC, ONLY: IEEE_IS_FINITE
+      IMPLICIT NONE
+      DOUBLE PRECISION X0,Y0,B,R,TMAX,P4(4),STEP,LG,LH,LHT,IT3
+      DOUBLE PRECISION VX,VY,VZ,SPEED,VT,NX,NY,X,DOT,DISC,DIST
+      DOUBLE PRECISION TEND,DT,T,TEMP,GETTEMP,RATIO
+      INTEGER I,J,NSTEPS
+      LG=0.D0
+      LH=0.D0
+      LHT=0.D0
+      IT3=0.D0
+      IF(R.LE.0.D0) RETURN
+      DO J=1,4
+        IF(.NOT.IEEE_IS_FINITE(P4(J)))
+     &       CALL JG_FAIL('non-finite shower-start momentum')
+      ENDDO
+      IF(P4(4).LE.0.D0) CALL JG_FAIL('nonpositive shower-start energy')
+      VX=P4(1)/P4(4)
+      VY=P4(2)/P4(4)
+      VZ=P4(3)/P4(4)
+      SPEED=SQRT(VX**2+VY**2+VZ**2)
+      VT=SQRT(VX**2+VY**2)
+      IF(SPEED.GT.1.D0+1.D-8)
+     &     CALL JG_FAIL('spacelike shower-start momentum')
+      IF(SPEED.EQ.0.D0) RETURN
+      TEND=MAX(0.D0,TMAX)
+C--The NTHICK support is the intersection of two discs of radius R.
+      IF(VT.GT.0.D0)THEN
+        NX=VX/VT
+        NY=VY/VT
+        LG=HUGE(LG)
+        DO J=1,2
+          X=X0+(2*J-3)*B/2.D0
+          DOT=X*NX+Y0*NY
+          DISC=DOT**2+R**2-X**2-Y0**2
+          IF(X**2+Y0**2.GT.R**2*(1.D0+1.D-10))
+     &         CALL JG_FAIL('production point outside NTHICK support')
+          DIST=MAX(0.D0,-DOT+SQRT(MAX(0.D0,DISC)))
+          LG=MIN(LG,DIST)
+        ENDDO
+        TEND=MIN(TEND,LG/VT)
+      ENDIF
+      IF(TEND.LE.0.D0) RETURN
+C--STEP bounds coordinate time (fm/c) and hence spatial step (fm).
+C--Never stop at the first zero: the temperature initially rises.
+      RATIO=TEND/STEP
+      IF(.NOT.IEEE_IS_FINITE(RATIO))
+     &     CALL JG_FAIL('geometry step requires too many intervals')
+      IF(RATIO.GT.10000000.D0)
+     &     CALL JG_FAIL('geometry step exceeds 10000000 intervals')
+      NSTEPS=MAX(1,CEILING(RATIO))
+      DT=TEND/DBLE(NSTEPS)
+      DO I=1,NSTEPS
+        T=(DBLE(I)-0.5D0)*DT
+        TEMP=GETTEMP(X0+VX*T,Y0+VY*T,VZ*T,T)
+        IF(.NOT.IEEE_IS_FINITE(TEMP))
+     &       CALL JG_FAIL('medium returned non-finite temperature')
+        IF(TEMP.GT.0.D0)THEN
+          LH=LH+SPEED*DT
+          LHT=LHT+VT*DT
+          IT3=IT3+TEMP**3*SPEED*DT
+        ENDIF
+      ENDDO
+      END
+
+      SUBROUTINE JG_CLOSE()
+      IMPLICIT NONE
+      INTEGER GUNIT,GPID(2),GLAST,IOS
+      LOGICAL GENABLED,GREADY
+      COMMON/JGINT/GUNIT,GPID,GLAST
+      COMMON/JGLOG/GENABLED,GREADY
+      SAVE /JGINT/,/JGLOG/
+      IF(.NOT.GENABLED) RETURN
+      CLOSE(GUNIT,IOSTAT=IOS)
+      IF(IOS.NE.0) CALL JG_FAIL('cannot close geometry file')
+      GENABLED=.FALSE.
+      END
+
+      SUBROUTINE JG_FAIL(MESSAGE)
+      USE, INTRINSIC :: ISO_FORTRAN_ENV, ONLY: ERROR_UNIT
+      IMPLICIT NONE
+      CHARACTER*(*) MESSAGE
+      WRITE(ERROR_UNIT,'(A)') '[jewel geometry] ERROR: '//MESSAGE
+      STOP 1
+      END
--- medium-simple.f
+++ medium-simple.f
@@ -829,0 +830,39 @@
+
+C--geometry-v1: medium accessors keep backend COMMON layouts isolated.
+      SUBROUTINE JG_MEDHEADER(U)
+      IMPLICIT NONE
+      INTEGER U,NF,A
+      COMMON/MEDPARAM/CENTRMIN,CENTRMAX,BREAL,CENTR,RAU,NF
+      DOUBLE PRECISION CENTRMIN,CENTRMAX,BREAL,CENTR,RAU
+      COMMON/MEDPARAMINT/TAUI,TI,TC,D3,ZETA3,D,
+     &     N0,SIGMANN,A,WOODSSAXON
+      DOUBLE PRECISION TAUI,TI,TC,D3,ZETA3,D,N0,SIGMANN
+      LOGICAL WOODSSAXON
+      COMMON/THICKFNC/RMAX,TA(100,2)
+      DOUBLE PRECISION RMAX,TA
+      COMMON/RAPMAX2/ETAMAX2
+      DOUBLE PRECISION ETAMAX2
+      WRITE(U,'(A)') '# medium=simple'
+      WRITE(U,'(A)') '# geometry_boundary=NTHICK finite support'
+      WRITE(U,'(A,ES24.16E3)') '# geometry_radius_fm=',TA(100,1)
+      WRITE(U,'(A,ES24.16E3)') '# taui_fm=',TAUI
+      WRITE(U,'(A,ES24.16E3)') '# ti_GeV=',TI
+      WRITE(U,'(A,ES24.16E3)') '# tc_GeV=',TC
+      WRITE(U,'(A,ES24.16E3)') '# medium_rapidity_max=',ETAMAX2
+      WRITE(U,'(A,I0)') '# mass_number=',A
+      WRITE(U,'(A,L1)') '# woodssaxon=',WOODSSAXON
+      END
+
+      SUBROUTINE JG_MEDSTATE(B,C,R,TMAX)
+      IMPLICIT NONE
+      DOUBLE PRECISION B,C,R,TMAX,GETLTIMEMAX
+      COMMON/MEDPARAM/CENTRMIN,CENTRMAX,BREAL,CENTR,RAU,NF
+      INTEGER NF
+      DOUBLE PRECISION CENTRMIN,CENTRMAX,BREAL,CENTR,RAU
+      COMMON/THICKFNC/RMAX,TA(100,2)
+      DOUBLE PRECISION RMAX,TA
+      B=BREAL
+      C=CENTR
+      R=TA(100,1)
+      TMAX=GETLTIMEMAX()
+      END
--- medium-vac.f
+++ medium-vac.f
@@ -214,0 +215,18 @@
+
+C--geometry-v1: vacuum has no physical medium geometry.
+      SUBROUTINE JG_MEDHEADER(U)
+      IMPLICIT NONE
+      INTEGER U
+      WRITE(U,'(A)') '# medium=vac'
+      WRITE(U,'(A)') '# geometry_boundary=none (vacuum)'
+      WRITE(U,'(A)') '# geometry_radius_fm=0'
+      END
+
+      SUBROUTINE JG_MEDSTATE(B,C,R,TMAX)
+      IMPLICIT NONE
+      DOUBLE PRECISION B,C,R,TMAX
+      B=0.D0
+      C=-1.D0
+      R=0.D0
+      TMAX=0.D0
+      END
PATCH_EOF
patch -p0 --forward --dry-run < custom-geometry.patch
patch -p0 --forward < custom-geometry.patch
check_sha jewel-2.6.0.f "$GEOMETRY_SHA256"
check_sha medium-simple.f "$GEOMETRY_MEDIUM_SHA256"
check_sha medium-vac.f "$GEOMETRY_VAC_SHA256"
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
for b in $(binaries); do cp "$b" "{{ prefix }}/bin/jewel-2.6.0-custom-${b#jewel-2.6.0-}"; done

# 3) patched binaries with the speed-ups
cat > custom-perf.patch <<'PATCH_EOF'
--- jewel-2.6.0.f
+++ jewel-2.6.0.f
@@ -4753,7 +4753,7 @@
 C--first figure out whether sibling has scattered or had a chance to scatter
 	mother = k(l,3)
 	if (k(mother,3).eq.0) return
-	call flush()
+C--perf-v1: stray call flush() removed (flushed every unit on every call)
 	if (k(mother,4).eq.l) then
 	  sib = k(mother,5)
 	else
--- medium-simple.f
+++ medium-simple.f
@@ -93,6 +93,10 @@
       DATA D3/0.9d0/
       DATA ZETA3/1.2d0/
 C--local variables
+C--perf-v1: per-event cache of GETTEMPMAX and of NPART at the centre
+      COMMON/MEDCACHE/BCACHE,TMAXC,NPART0,NP0SET
+      DOUBLE PRECISION BCACHE,TMAXC,NPART0
+      LOGICAL NP0SET
       INTEGER I,LUN,POS,IOS,id,mass
 	double precision etam
       CHARACTER*100 BUFFER,LABEL,tempbuf
@@ -102,6 +106,8 @@
 
 	etamax2 = etam
 	logfid = id
+      BCACHE=-1.D0
+      NP0SET=.FALSE.
 
       IOS=0
       LUN=77
@@ -199,6 +205,8 @@
       CALL CALCTA
 C--calculate geometrical cross section
       CALL CALCXSECTION
+      BCACHE=-1.D0
+      NP0SET=.FALSE.
 
       END
 
@@ -488,6 +496,10 @@
 C--local variables
       DOUBLE PRECISION X4,Y4,Z4,T4,TAU,NPART,EPS0,EPSIN,TEMPIN,PI,
      &NTHICK,ys
+C--perf-v1: per-event cache of GETTEMPMAX and of NPART at the centre
+      COMMON/MEDCACHE/BCACHE,TMAXC,NPART0,NP0SET
+      DOUBLE PRECISION BCACHE,TMAXC,NPART0
+      LOGICAL NP0SET
       DATA PI/3.141592653589793d0/
 
       GETTEMP=0.D0
@@ -506,8 +518,12 @@
          EPS0=(16.*8.+7.*2.*6.*NF)*PI**2*TI**4/240.
 !         EPSIN=EPS0*NPART(X4-BREAL/2.,Y4,X4+BREAL/2.,Y4)
 !     &        *PI*RAU**2/(2.*A)
+         IF(.NOT.NP0SET)THEN
+           NPART0=NPART(0.d0,0.d0,0.d0,0.d0)
+           NP0SET=.TRUE.
+         ENDIF
 	   EPSIN=EPS0*NPART(X4-BREAL/2.,Y4,X4+BREAL/2.,Y4)/
-     &        NPART(0.d0,0.d0,0.d0,0.d0)
+     &        NPART0
          TEMPIN=(EPSIN*240./(PI**2*(16.*8.+7.*2.*6.*NF)))**0.25
       ELSE
          TEMPIN=TI
@@ -538,7 +554,15 @@
       LOGICAL WOODSSAXON
 C--function call
       DOUBLE PRECISION GETTEMP
-      GETTEMPMAX=GETTEMP(0.D0,0.D0,0.D0,TAUI)
+C--perf-v1: per-event cache of GETTEMPMAX and of NPART at the centre
+      COMMON/MEDCACHE/BCACHE,TMAXC,NPART0,NP0SET
+      DOUBLE PRECISION BCACHE,TMAXC,NPART0
+      LOGICAL NP0SET
+      IF(BREAL.NE.BCACHE)THEN
+        TMAXC=GETTEMP(0.D0,0.D0,0.D0,TAUI)
+        BCACHE=BREAL
+      ENDIF
+      GETTEMPMAX=TMAXC
       END
 
 
PATCH_EOF
patch -p0 --forward --dry-run < custom-perf.patch
patch -p0 --forward < custom-perf.patch
check_sha jewel-2.6.0.f "$PATCHED_SHA256"
check_sha medium-simple.f "$PATCHED_MEDIUM_SHA256"
check_sha medium-vac.f "$GEOMETRY_VAC_SHA256"
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
for b in $(binaries); do cp "$b" "{{ prefix }}/bin/jewel-2.6.0-custom-perf-${b#jewel-2.6.0-}"; done
rm -f *.o $(binaries)

# leave the source tree stock, so the stock recipe logic still applies to it
cp jewel-2.6.0.f.stock jewel-2.6.0.f
cp medium-simple.f.stock medium-simple.f
cp medium-vac.f.stock medium-vac.f

cp *.dat {{ prefix }}/settings/
for f in *.txt README GUIDELINES; do [ -f "$f" ] && cp "$f" {{ prefix }}/info/ || true; done
cp custom-partons.patch custom-geometry.patch custom-perf.patch {{ prefix }}/info/
cat > {{ prefix }}/info/CUSTOM-PATCHES.txt <<INFO_EOF
JEWEL 2.6.0, custom patch set: $CUSTOM_PATCHSET
stock sources        jewel-2.6.0.f   sha256 $STOCK_SHA256
                     medium-simple.f sha256 $STOCK_MEDIUM_SHA256
                     medium-vac.f sha256 $STOCK_VAC_SHA256
partons-only source  jewel-2.6.0.f   sha256 $PARTONS_SHA256
custom sources       jewel-2.6.0.f   sha256 $GEOMETRY_SHA256   (partons-v1+geometry-v1)
                     medium-simple.f sha256 $GEOMETRY_MEDIUM_SHA256
                     medium-vac.f sha256 $GEOMETRY_VAC_SHA256
custom-perf sources  jewel-2.6.0.f   sha256 $PATCHED_SHA256   (partons-v1+geometry-v1+perf-v1)
                     medium-simple.f sha256 $PATCHED_MEDIUM_SHA256
                     medium-vac.f sha256 $GEOMETRY_VAC_SHA256
stock binaries:       $(echo $built)
custom binaries:      $(cd {{ prefix }}/bin && ls jewel-2.6.0-custom-* | grep -v custom-perf | xargs)
custom-perf binaries: $(cd {{ prefix }}/bin && echo jewel-2.6.0-custom-perf-*)
patches: custom-partons.patch (outgoing hard partons as HepMC status 23; PARI(17) as event scale)
         custom-geometry.patch (opt-in PPJJ production point and straight-ray medium exposure)
         custom-perf.patch    (speed only: cached medium constants, stray flush removed)
INFO_EOF
