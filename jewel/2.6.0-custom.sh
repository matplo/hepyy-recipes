set -e
# JEWEL 2.6.0 with custom patches, installed next to the stock binaries.
#
#   bin/jewel-2.6.0-simple, bin/jewel-2.6.0-vac                stock JEWEL 2.6.0
#   bin/jewel-2.6.0-custom-simple, bin/jewel-2.6.0-custom-vac  patched (list below)
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
CUSTOM_PATCHSET="partons-v1"
STOCK_SHA256="78b39f19513c3633c00d45b22f0803c0873a93d98a536d66efc9277255bf5b81"
PATCHED_SHA256="5ab26243f3512e6a345e6c12dd5d64e0213b5cd1815ad0141bd968142f204761"

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

# a re-run in a cached source tree may start from the patched source
if [ -f jewel-2.6.0.f.stock ]; then cp jewel-2.6.0.f.stock jewel-2.6.0.f; fi
cp jewel-2.6.0.f jewel-2.6.0.f.stock
stock_sha=$(sha256_of jewel-2.6.0.f)
if [ "$stock_sha" != "$STOCK_SHA256" ]; then
  echo "[jewel] ERROR: jewel-2.6.0.f is not the source the $CUSTOM_PATCHSET patches were made for"
  echo "[jewel]        expected sha256 $STOCK_SHA256, found $stock_sha"
  exit 1
fi

mkdir -p {{ prefix }}/bin {{ prefix }}/settings {{ prefix }}/info

binaries () { for b in jewel-2.6.0-*; do [ -f "$b" ] && [ -x "$b" ] && echo "$b"; done; }

# 1) stock binaries (every jewel-2.6.0-* executable the Makefile builds, as the stock recipe)
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
built=$(binaries)
[ -n "$built" ] || { echo "[jewel] ERROR: make produced no jewel-2.6.0-* binaries"; exit 1; }
cp $built {{ prefix }}/bin/

# 2) patched binaries
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
patched_sha=$(sha256_of jewel-2.6.0.f)
if [ "$patched_sha" != "$PATCHED_SHA256" ]; then
  echo "[jewel] ERROR: patched jewel-2.6.0.f has sha256 $patched_sha, expected $PATCHED_SHA256"
  exit 1
fi
rm -f *.o $(binaries)
make LHAPDF_PATH="$lhapdf_prefix/lib"
for b in $(binaries); do cp "$b" "{{ prefix }}/bin/jewel-2.6.0-custom-${b#jewel-2.6.0-}"; done

# leave the source tree stock, so the stock recipe logic still applies to it
cp jewel-2.6.0.f.stock jewel-2.6.0.f

cp *.dat {{ prefix }}/settings/
for f in *.txt README GUIDELINES; do [ -f "$f" ] && cp "$f" {{ prefix }}/info/ || true; done
cp custom-partons.patch {{ prefix }}/info/
cat > {{ prefix }}/info/CUSTOM-PATCHES.txt <<INFO_EOF
JEWEL 2.6.0, custom patch set: $CUSTOM_PATCHSET
stock source   jewel-2.6.0.f sha256 $STOCK_SHA256
patched source jewel-2.6.0.f sha256 $PATCHED_SHA256
stock binaries:   $(echo $built)
patched binaries: $(cd {{ prefix }}/bin && echo jewel-2.6.0-custom-*)
patches: custom-partons.patch (outgoing hard partons as HepMC status 23; PARI(17) as event scale)
INFO_EOF
