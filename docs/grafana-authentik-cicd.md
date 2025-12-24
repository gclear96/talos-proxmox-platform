**A large chunk** of Grafana can be managed “as code” in a GitOps workflow (Helm/Kustomize + ArgoCD) using:

* **Grafana provisioning** (files mounted into `provisioning/…`)
* Kubernetes-native secret management (SealedSecrets / External Secrets / SOPS, etc.)

Below is a practical guide and an honest view of what’s “fully declarative” vs. what still tends to be “stateful / API-driven”.

---

## How much can be declarative?

### Grafana

**Very good coverage** for “infrastructure-ish” configuration:

* **Config file settings** (everything you’d normally set in `grafana.ini`, including OIDC/OAuth settings, server URLs, feature toggles, etc.).
* **Data sources** via provisioning YAML (`provisioning/datasources`). Grafana supports versioning, pruning, and deletes in provisioning files. ([Grafana Labs][1])
* **Dashboards** via provisioning (`provisioning/dashboards`) and dashboard JSON on disk; Grafana applies provisioning at startup and keeps it updated while running. ([Grafana Labs][2])
* **Unified Alerting** resources (rules, contact points, notification policies, etc.) via file provisioning (`provisioning/alerting`). Provisioned alerting resources are *intentionally not editable in the UI*; change the file + restart or do a hot reload via the Admin API. ([Grafana Labs][3])

**Less declarative / usually needs API/Terraform/operator:**

* Users, teams, orgs, folder permissions, API keys, UI preferences, ad-hoc manual dashboards created in the UI, etc. (Some of this can be done with Grafana’s HTTP API or Terraform provider; provisioning doesn’t cover everything.)

**Optional new direction:** Grafana v12 introduced “Git Sync” / “Observability as Code” workflows, but they’re documented as experimental in nightly releases and don’t come with normal support/SLA. ([Grafana Labs][4])

---

### authentik

authentik configuration is **not** managed in this repo anymore.

We plan to manage authentik via Terraform (authentik provider) in a separate repo. Keep this repo focused on platform services and their ingress/secret wiring.

---

## A GitOps guide: Grafana + authentik fully reproducible on Kubernetes

### 1) Organize your repo for “rendered config”

A common layout that works well with ArgoCD:

```text
clusters/
  prod/
    argocd-apps/
      grafana-app.yaml
      authentik-app.yaml
apps/
  grafana/
    values.yaml
    provisioning/
      datasources/
        prometheus.yaml
      dashboards/
        providers.yaml
        dashboards/
          cluster.json
      alerting/
        contact-points.yaml
        rules.yaml
  authentik/
    values.yaml
```

Keep *renderable text* (values, provisioning) in Git. Generate Kubernetes Secrets via your secret toolchain (SOPS, External Secrets, etc.).

---

## 2) authentik configuration (Terraform)

authentik is managed outside this repo using Terraform. Keep Helm values limited to runtime wiring (ingress, database, logging), and manage identity resources (apps, providers, flows, policies) via Terraform.

---

## 3) Grafana: treat provisioning files as the source of truth

### 3.1 Use file provisioning for data sources and dashboards

Grafana’s provisioning directory structure (datasources/dashboards) is well-documented, and provisioning is applied at startup and updated while running. ([Grafana Labs][2])

**Data sources**: use a YAML like the documented format (with `apiVersion: 1`, optional `deleteDatasources`, `prune`, and `version`). ([Grafana Labs][1])

**Dashboards**: store dashboard JSON in Git and provision it via a dashboard provider file. ([Grafana Labs][2])

### 3.2 Provision alerting resources (and embrace “no UI edits”)

For Grafana Alerting provisioning:

* You *cannot edit file-provisioned alerting resources in the UI*.
* Update the provisioning files and restart, or do a hot reload (Admin API). ([Grafana Labs][3])
* The docs also describe exporting existing alerting resources to a provisioning file—useful for bootstrapping from a manually-created setup. ([Grafana Labs][3])

### 3.3 Wire Grafana auth to authentik (OIDC/OAuth)

This is usually two pieces:

1. **Terraform** creates the authentik application/provider + mappings/scopes.
2. **grafana.ini (or Helm values)** configures generic OAuth/OIDC against authentik.

Because endpoint details and client settings vary by authentik provider setup, a robust approach is:

* Get the provider’s OpenID details from authentik (UI or discovery endpoint),
* Set Grafana’s OAuth config accordingly,
* Keep the *client secret* out of Git (inject via Secret → env/file).

---

## 4) What will still bite you (and how to address it)

### Grafana gaps

Provisioning is great for “platform config,” but anything that’s inherently user-driven (UI-edited dashboards, personal preferences, ad-hoc teams/permissions) is better handled by:

* **Policy:** “All dashboards/alerts must come from Git.”
* **Automation:** Terraform/provider/API for the bits you truly must manage centrally (teams, folder perms, etc.).

### authentik gaps

Terraform will own authentik state; treat the authentik UI as read-only except for debugging.

---

## 5) A “minimum viable GitOps” checklist

* [ ] ArgoCD deploys **Helm releases** for Grafana + authentik.
* [ ] All Grafana **datasources/dashboards/alerting** come from provisioning files in Git. ([Grafana Labs][1])
* [ ] authentik **apps/providers/flows/policies** come from Terraform.
* [ ] You have a stance on “UI changes”: either forbid them for provisioned resources, or explicitly decide where state is allowed to live.

---
[1]: https://grafana.com/docs/grafana/latest/administration/provisioning/ "Provision Grafana | Grafana documentation
"
[2]: https://grafana.com/tutorials/provision-dashboards-and-data-sources/ "Provision dashboards and data sources | Grafana Labs
"
[3]: https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/ "Use configuration files to provision alerting resources | Grafana documentation
"
[4]: https://grafana.com/docs/grafana/latest/as-code/observability-as-code/provision-resources/ "Provision resources and sync dashboards | Grafana documentation
"
[10]: https://docs.goauthentik.io/install-config/configuration/ "Configuration | authentik"
