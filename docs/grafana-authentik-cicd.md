**A large chunk** of both Grafana and authentik can be managed “as code” in a GitOps workflow (Helm/Kustomize + ArgoCD). The trick is to lean on:

* **Grafana provisioning** (files mounted into `provisioning/…`)
* **authentik blueprints** (declarative YAML objects, mounted into the worker)
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

authentik is *designed* for declarative management via **Blueprints**:

* Blueprints are YAML files that can “template, automate, and distribute” authentik configuration without external tools. ([docs.goauthentik.io][5])
* Blueprints can be **mounted into the authentik worker** and are applied regularly (docs mention every ~60 minutes for blueprint instances). ([version-2025-4.goauthentik.io][6])
* Blueprints support “YAML tags” so you can pull sensitive values from **environment variables** (`!Env`) or **files** (`!File`) instead of hardcoding secrets in Git. ([docs.goauthentik.io][7])
* Helm chart support: mount blueprint YAMLs from **ConfigMaps and Secrets** into `/blueprints/mounted/...` for automatic discovery/application. ([DeepWiki][8])

**Limits to expect:**

* If you “bootstrap in UI then export,” note that **write-only fields (e.g., OAuth provider secret key)** won’t be included in exported blueprints. ([docs.goauthentik.io][9])
  (So you’ll need to supply those via `!Env`/`!File` or another secret injection strategy.)
* Some objects won’t export cleanly due to dependencies; expect some cleanup/splitting after export. ([docs.goauthentik.io][9])
* Runtime state (sessions, tokens created by users, etc.) is not something you “declaratively provision” in a meaningful way.

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
    blueprints/
      cm/
        base-flows.yaml
        apps-grafana.yaml
      secret/
        oauth-secrets.yaml
```

Keep *renderable text* (values, provisioning, blueprints) in Git. Generate Kubernetes Secrets via your secret toolchain (SOPS, External Secrets, etc.).

---

## 2) authentik: make it declarative with Blueprints

### 2.1 Configure authentik via Helm + env vars

authentik’s core runtime config is explicitly designed to be set via **environment variables**. ([docs.goauthentik.io][10])

Use Helm values (via ArgoCD) to set:

* ingress/hostnames
* database connectivity
* email, logging, etc.
* mounting blueprints (next section)

### 2.2 Mount blueprints from ConfigMaps/Secrets

The Helm chart supports listing ConfigMaps/Secrets that contain `.yaml` keys, which get mounted under `/blueprints/mounted/...` and discovered/applied. ([DeepWiki][8])

Example Helm values snippet:

```yaml
blueprints:
  configMaps:
    - authentik-blueprints
  secrets:
    - authentik-blueprints-secret
```

Create:

* `ConfigMap/authentik-blueprints` with non-sensitive blueprint YAMLs
* `Secret/authentik-blueprints-secret` with sensitive blueprint YAMLs (or just references to env/file tags)

### 2.3 Write blueprints that auto-instantiate

Blueprint file structure supports an “auto instantiate” annotation (defaults to true). ([docs.goauthentik.io][11])

So your blueprint YAML can include something like:

```yaml
metadata:
  name: "apps-grafana"
  annotations:
    blueprints.goauthentik.io/instantiate: "true"
```

### 2.4 Handle secrets correctly

Because exported blueprints omit write-only fields like OAuth provider secrets ([docs.goauthentik.io][9]), design your blueprints to *reference* secrets:

* `!Env` reads from env vars ([docs.goauthentik.io][7])
* `!File` reads from a mounted file ([docs.goauthentik.io][7])

This lets you keep OAuth client secrets, signing keys, etc. out of Git while still being fully reproducible.

### 2.5 Bootstrap from an existing instance (recommended workflow)

1. Configure authentik once (UI) in a scratch/test instance.
2. Export most objects to a blueprint with `ak export_blueprint`. ([docs.goauthentik.io][9])
3. Split that export into multiple files (flows vs. apps vs. providers).
4. Replace missing write-only secrets with `!Env` / `!File`. ([docs.goauthentik.io][7])
5. Commit + let ArgoCD roll it out.

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

1. **authentik blueprint** creates the application/provider + mappings/scopes.
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

Blueprints cover a lot, but:

* Exports won’t include write-only secrets ([docs.goauthentik.io][9]) → always plan secret injection.
* Some objects may not export due to dependencies ([docs.goauthentik.io][9]) → expect cleanup.

---

## 5) A “minimum viable GitOps” checklist

* [ ] ArgoCD deploys **Helm releases** for Grafana + authentik.
* [ ] All Grafana **datasources/dashboards/alerting** come from provisioning files in Git. ([Grafana Labs][1])
* [ ] authentik **apps/providers/flows/policies** come from blueprints mounted from ConfigMaps/Secrets. ([DeepWiki][8])
* [ ] Secrets are injected via `!Env` / `!File` in authentik blueprints (and via K8s secrets for Grafana). ([docs.goauthentik.io][7])
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
[5]: https://docs.goauthentik.io/customize/blueprints/ "Blueprints | authentik"
[6]: https://version-2025-4.goauthentik.io/docs/customize/blueprints/?utm_source=chatgpt.com "Blueprints - authentik"
[7]: https://docs.goauthentik.io/customize/blueprints/v1/tags/ "YAML Tags | authentik"
[8]: https://deepwiki.com/goauthentik/helm/2.5.2-blueprints-configuration "Blueprints Configuration | goauthentik/helm | DeepWiki"
[9]: https://docs.goauthentik.io/customize/blueprints/export/ "Export configurations to blueprints | authentik"
[10]: https://docs.goauthentik.io/install-config/configuration/ "Configuration | authentik"
[11]: https://docs.goauthentik.io/customize/blueprints/v1/structure/?utm_source=chatgpt.com "File structure - authentik"

