set -e
# JEWEL 2.6.0 with custom patches, installed next to the stock binaries. Three builds:
#
#   bin/jewel-2.6.0-{simple,vac}              stock JEWEL 2.6.0
#   bin/jewel-2.6.0-custom-{simple,vac}       stock + partons-v1
#   bin/jewel-2.6.0-custom-perf-{simple,vac}  stock + partons-v1 + perf-v1 (all patches)
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
#   Nothing is added for EEJJ and PPDY events or for the long output.
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
CUSTOM_PATCHSET="partons-v1+perf-v1"
STOCK_SHA256="78b39f19513c3633c00d45b22f0803c0873a93d98a536d66efc9277255bf5b81"
STOCK_MEDIUM_SHA256="a5f5a16d984cf84d28c2c789f72557a64b85cb6ae51bc9f395b1f2a7f4e2bd38"
PARTONS_SHA256="5ab26243f3512e6a345e6c12dd5d64e0213b5cd1815ad0141bd968142f204761"
PATCHED_SHA256="2732e04ef15dcc8a631f339acf64994e82d22e7921c234d3fc2442ab14f4e3dc"
PATCHED_MEDIUM_SHA256="991f85f5abdac3d69512543b901d41ad21ae8bb7b333dfd84ef01ec21e5d0b5f"

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
for f in jewel-2.6.0.f medium-simple.f; do
  if [ -f "$f.stock" ]; then cp "$f.stock" "$f"; fi
  cp "$f" "$f.stock"
done
check_sha jewel-2.6.0.f "$STOCK_SHA256"
check_sha medium-simple.f "$STOCK_MEDIUM_SHA256"

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
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
for b in $(binaries); do cp "$b" "{{ prefix }}/bin/jewel-2.6.0-custom-perf-${b#jewel-2.6.0-}"; done
rm -f *.o $(binaries)

# leave the source tree stock, so the stock recipe logic still applies to it
cp jewel-2.6.0.f.stock jewel-2.6.0.f
cp medium-simple.f.stock medium-simple.f

cp *.dat {{ prefix }}/settings/
for f in *.txt README GUIDELINES; do [ -f "$f" ] && cp "$f" {{ prefix }}/info/ || true; done
cp custom-partons.patch custom-perf.patch {{ prefix }}/info/
cat > {{ prefix }}/info/CUSTOM-PATCHES.txt <<INFO_EOF
JEWEL 2.6.0, custom patch set: $CUSTOM_PATCHSET
stock sources        jewel-2.6.0.f   sha256 $STOCK_SHA256
                     medium-simple.f sha256 $STOCK_MEDIUM_SHA256
custom sources       jewel-2.6.0.f   sha256 $PARTONS_SHA256   (partons-v1)
                     medium-simple.f stock
custom-perf sources  jewel-2.6.0.f   sha256 $PATCHED_SHA256   (partons-v1+perf-v1)
                     medium-simple.f sha256 $PATCHED_MEDIUM_SHA256
stock binaries:       $(echo $built)
custom binaries:      $(cd {{ prefix }}/bin && ls jewel-2.6.0-custom-* | grep -v custom-perf | xargs)
custom-perf binaries: $(cd {{ prefix }}/bin && echo jewel-2.6.0-custom-perf-*)
patches: custom-partons.patch (outgoing hard partons as HepMC status 23; PARI(17) as event scale)
         custom-perf.patch    (speed only: cached medium constants, stray flush removed)
INFO_EOF
