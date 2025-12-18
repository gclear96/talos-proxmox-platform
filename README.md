# Talos homelab platform repo (Argo CD)

This repo is meant to be the “platform” repo in an App-of-Apps / ApplicationSet style setup.

- The bootstrap repo installs Argo CD + a root Application pointing at `clusters/homelab/bootstrap`.
- That directory contains:
  - an AppProject (`platform`)
  - one or more ApplicationSets which generate Applications for each platform component.

This scaffold uses **wrapper Helm charts** stored in-repo at `apps/<name>/chart/`.
Argo CD can render Helm charts from a Git path (when it finds a Chart.yaml).

## Layout

- `clusters/homelab/bootstrap/` – applied by the root app
- `apps/*/chart/` – wrapper charts (dependencies pinned here)
- `clusters/homelab/values/` – optional place for per-cluster values (not used yet)

## Add a new platform app

1) Create `apps/<new-app>/chart/Chart.yaml` with a dependency on an upstream chart.
2) Add values in `apps/<new-app>/chart/values.yaml`.
3) The ApplicationSet directory generator will discover it automatically.
