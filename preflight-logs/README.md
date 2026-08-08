# Preflight logs

This folder collects the readable logs produced by the per-demo preflight checks
(`moduleN/scripts/*.preflight.sh`). Each run writes one file here:

```
preflight-logs/m<module>-demo<n>-<name>.log
```

for example `preflight-logs/m2-demo5-traces-logs-metrics-quality.log`.

These `.log` files are **generated artifacts** — regenerated on every preflight
run — so they are git-ignored (see `.gitignore`). Only this README is tracked, so
the folder always exists after a clone. Run a check to populate it, e.g.:

```bash
bash module2/scripts/m2-demo5-traces-logs-metrics-quality.preflight.sh
```

Upgrading from an older checkout that left loose `module*/*preflight_log.txt`
files behind? Collect them into this folder (renamed to the scheme above) with:

```bash
bash scripts/collect-preflight-logs.sh
```
