set -e
build_dir={{ srcdir }}-build
mkdir -p "$build_dir"
cd "$build_dir"
cmake {{ srcdir }} \
  -DCMAKE_INSTALL_PREFIX={{ prefix }} \
  -DCMAKE_BUILD_TYPE=Release \
  -DPython3_EXECUTABLE=$(which python3) \
  -Dbuiltin_xrootd=OFF \
  -Dxrootd=OFF \
  -Dvmc=OFF \
  -Dmathmore=ON \
  -Dxml=ON \
  -Dunfold=ON \
  -Dbuiltin_vdt=ON \
  -Dbuiltin_gif=ON \
  -Dbuiltin_gl2ps=ON
cmake --build . --target install -- -j {{ n_cores }}
