# Grafana Alerting (GitOps)

This folder contains Grafana Unified Alerting provisioning files mounted into
`/etc/grafana/provisioning/alerting` by the wrapper chart.

Current defaults are intentionally minimal:

- **contact-points.yaml**: a placeholder webhook contact point (replace with real receivers)
- **notification-policies.yaml**: a single root policy routing to the default contact point
- **alert-rules.yaml**: a placeholder rule that never fires (replace with real alerts)

Notes:

- File-provisioned alerting resources are **read-only** in the Grafana UI.
- Update these files and restart Grafana (or hot-reload via Admin API) to apply changes.
