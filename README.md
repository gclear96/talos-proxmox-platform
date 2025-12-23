# Talos homelab platform repo (Argo CD)

This repo is meant to be the “platform” repo in an App-of-Apps / ApplicationSet style setup.

- The bootstrap repo installs Argo CD + a root Application pointing at `clusters/homelab/bootstrap`.
- That directory contains:
  - an AppProject (`platform`)
  - one or more ApplicationSets which generate Applications for each platform component.

This scaffold uses **wrapper Helm charts** stored in-repo at `apps/<name>/chart/`.
Argo CD can render Helm charts from a Git path (when it finds a Chart.yaml).

For apps that are distributed primarily via **Helm OCI** (like Forgejo), this repo uses a separate
ApplicationSet (`clusters/homelab/bootstrap/applicationset-oci.yaml`).

## First-time setup

- Update `clusters/homelab/bootstrap/project-platform.yaml` `spec.sourceRepos` to your actual GitHub/Forgejo repo URL(s).
- Update `clusters/homelab/bootstrap/applicationset-wrapped-charts.yaml` `repoURL` (template) to match.
- Update `clusters/homelab/bootstrap/applicationset-oci.yaml` (Forgejo `ingressHost`, chart version if desired).
- Update `clusters/homelab/bootstrap/applicationset-oci-runners.yaml` with your Forgejo runner config once Forgejo is up.
- Set per-cluster overrides in `clusters/homelab/values/` (example: `ingress-nginx.yaml` for LoadBalancer).
- If you plan to use cert-manager ACME issuers, edit `clusters/homelab/values/cert-manager.yaml` and install a DNS-01 webhook for Porkbun (see below).
- `hack/set-repourl.sh` can help rewrite repoURL strings during cutover.

## Currently deployed apps

- Wrapper charts (`apps/*/chart`):
  - kube-prometheus-stack `80.6.0`
  - loki `6.49.0`
  - cert-manager `1.19.2`
  - porkbun-webhook `0.1.5`
  - ingress-nginx `4.14.1`
  - metrics-server `3.13.0`
  - external-secrets `1.2.0`
  - vault `0.31.0`
  - longhorn `1.10.1`
  - metallb `0.15.3`
  - authentik `2025.10.3`
- OCI apps:
  - Forgejo (`oci://code.forgejo.org/forgejo-helm/forgejo`, pinned `15.0.3`)
  - Forgejo runner (`oci://codeberg.org/wrenix/helm-charts/forgejo-runner`, pinned `0.6.17`)

## Namespaces

Wrapper-chart apps are deployed to fixed namespaces for production-style separation:

- `ingress-nginx` → `ingress-nginx`
- `cert-manager` → `cert-manager`
- `porkbun-webhook` → `cert-manager`
- `metallb` → `metallb-system`
- `longhorn` → `longhorn-system`
- `metrics-server` → `metrics-server`
- `external-secrets` → `external-secrets`
- `kube-prometheus-stack` → `monitoring`
- `loki` → `loki`
- `vault` → `vault`

Additional apps can be enabled by adding entries to
`clusters/homelab/bootstrap/applicationset-wrapped-charts.yaml` and creating
per-app overrides in `clusters/homelab/values/` as needed.

## Forgejo admin secret (no secrets in Git)

The Forgejo chart is configured to read admin credentials from a Secret named `forgejo-admin`.

In this repo, `clusters/homelab/bootstrap/external-secrets-vault-forgejo.yaml` provisions it via
External Secrets + Vault (Kubernetes auth).

Forgejo is set to `forgejo.k8s.magomago.moe` in `clusters/homelab/bootstrap/applicationset-oci.yaml`.

## Forgejo runner (no secrets in Git)

The Forgejo runner chart is included as an OCI ApplicationSet in
`clusters/homelab/bootstrap/applicationset-oci-runners.yaml`. You must supply the Forgejo
URL and a runner registration token (typically via a Secret referenced in values). Update the
inline Helm values in that ApplicationSet after you create the Secret.

## Per-cluster values

The ApplicationSet for wrapper charts loads a per-cluster values file if present:

- `clusters/homelab/values/<app>.yaml`

Missing files are ignored, so you only need overrides for the apps you customize. For example,
`clusters/homelab/values/ingress-nginx.yaml` currently sets `service.type: LoadBalancer`.

## Cert-manager ClusterIssuers (DNS-01)

ClusterIssuers are rendered by the cert-manager wrapper chart using per-cluster values in
`clusters/homelab/values/cert-manager.yaml`. This ensures the CRDs are installed before the
ClusterIssuer resources are applied.

Porkbun is not a built-in cert-manager DNS provider, so a Porkbun DNS-01 webhook is included via
the `porkbun-webhook` chart. The webhook group name is set to `acme.porkbun.magomago.moe` in
`clusters/homelab/values/porkbun-webhook.yaml`, and the ClusterIssuers reference it. The
`certManager.serviceAccountName` value must match the cert-manager Helm release name (this repo
uses `platform-cert-manager`). `certManager.secretName` should match the Porkbun API secret name
(`porkbun-key`).

Create the DNS-01 secret manually (no secrets in Git):

```bash
kubectl -n cert-manager create secret generic porkbun-key \
  --from-literal=api-key=REPLACE_ME \
  --from-literal=secret-key=REPLACE_ME
```

## App prerequisites and follow-ups

- MetalLB: IP pools and advertisements are configured in `clusters/homelab/values/metallb.yaml`
  (we pin ARP announcements to a specific NIC via `l2Advertisements[].interfaces`, e.g. `ens18`;
  `l2Advertisements[].nodeSelectors` are intentionally unset to keep HA).
- Longhorn: requires node prerequisites (iSCSI, kernel modules, and Talos extensions).
- Vault: configure storage backend and unseal strategy; defaults are not production-ready.
- Authentik: database password + secret key are sourced from Vault (`authentik/env`); configure email + initial setup before exposing it broadly.

## Argo CD ingress (prod cert)

An Argo CD ingress is defined in `clusters/homelab/bootstrap/argocd-ingress.yaml`:

- Host: `argocd.k8s.magomago.moe`
- TLS: cert-manager `letsencrypt-prod` (secret `argocd-tls-prod`)
- Backend: `argo-cd-argocd-server` on port 443 (HTTPS)

Point `argocd.k8s.magomago.moe` to your ingress LoadBalancer IP, then verify:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl -n argocd get ingress argocd
```

## Layout

- `clusters/homelab/bootstrap/` – applied by the root app
- `apps/*/chart/` – wrapper charts (dependencies pinned here)
- `clusters/homelab/values/` – per-cluster values overrides

## Add a new platform app

1) Create `apps/<new-app>/chart/Chart.yaml` with a dependency on an upstream chart.
2) Add values in `apps/<new-app>/chart/values.yaml`.
3) Add an entry to `clusters/homelab/bootstrap/applicationset-wrapped-charts.yaml` with the desired namespace.
