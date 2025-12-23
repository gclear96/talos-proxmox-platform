# Grafana dashboards (GitOps)

Put Grafana dashboard JSON files in this folder (`*.json`).

The wrapper chart renders them into `ConfigMap/grafana-dashboards` (labelled `grafana_dashboard=1`), which the kube-prometheus-stack Grafana sidecar discovers and loads automatically.

