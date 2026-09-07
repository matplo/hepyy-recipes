set -e

python3 -m pip install setuptools wheel --quiet
python3 -m pip install \
    --force-reinstall \
    --target {{ prefix }} \
    "git+https://github.com/matplo/hepyy-utils.git@main"

mkdir -p {{ prefix }}/bin

# pip --target behavior varies across pip versions for console scripts.
# Install explicit wrappers so hepyy modulefiles reliably expose them.
cat > {{ prefix }}/bin/jewel_prepare <<'EOF'
#!/usr/bin/env bash
export PYTHONPATH="{{ prefix }}:${PYTHONPATH:-}"
exec python3 -m heppyyier_utils.jewel.cli prepare "$@"
EOF

cat > {{ prefix }}/bin/jewel_run <<'EOF'
#!/usr/bin/env bash
export PYTHONPATH="{{ prefix }}:${PYTHONPATH:-}"
exec python3 -m heppyyier_utils.jewel.cli run "$@"
EOF

cat > {{ prefix }}/bin/jewel_convert <<'EOF'
#!/usr/bin/env bash
export PYTHONPATH="{{ prefix }}:${PYTHONPATH:-}"
exec python3 -m heppyyier_utils.jewel.cli convert "$@"
EOF

cat > {{ prefix }}/bin/jewel_pipeline <<'EOF'
#!/usr/bin/env bash
export PYTHONPATH="{{ prefix }}:${PYTHONPATH:-}"
exec python3 -m heppyyier_utils.jewel.cli pipeline "$@"
EOF

chmod +x {{ prefix }}/bin/jewel_prepare {{ prefix }}/bin/jewel_run {{ prefix }}/bin/jewel_convert {{ prefix }}/bin/jewel_pipeline
PYTHONPATH={{ prefix }} python3 -c "import heppyyier_utils; import heppyyier_utils.jewel; print('[hepyy-utils]', heppyyier_utils.__version__)"
