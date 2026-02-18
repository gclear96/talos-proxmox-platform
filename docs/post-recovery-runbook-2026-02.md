# Post-Recovery Runbook (2026-02)

This runbook captures the recovery that restored SSO and GitOps after storage-side data loss and Vault/Authentik resets.

## Scope

- Cluster: `talos-admin-1`
- Date window: 2026-02-18 to 2026-02-19
- Affected systems: Vault, Authentik, External Secrets, Forgejo runner, Argo CD repo access, Longhorn teardown

## Symptoms Seen

- Vault unavailable (`security barrier not initialized`, no usable auth methods)
- Authentik token/login failures after DB reset
- Argo CD app comparisons failing due missing Forgejo repos/credentials
- ExternalSecrets provider errors due missing/invalid Vault data
- Forgejo runner failing with `unauthenticated: unregistered runner`

## Recovery Sequence

1. Restore Authentik admin access and API token.
2. Reconcile `authentik-terraform-repo` state and re-apply Authentik resources.
3. Re-initialize and unseal Vault, then re-apply `vault-terraform-repo`.
4. Backfill required Vault KV paths used by External Secrets.
5. Re-register Forgejo runner and refresh runner secrets.
6. Recreate/push Forgejo mirror repos and refresh Argo CD.
7. Remove Longhorn from GitOps and finish in-cluster decommission.

## High-Value Commands

Use kubeconfig from bootstrap repo:

```bash
export KUBECONFIG=talos-proxmox-bootstrap-repo/out/talos-admin-1.kubeconfig
```

### 1) Authentik access

```bash
kubectl -n authentik get pods -o wide
kubectl -n authentik exec -it <authentik-server-pod> -c server -- ak changepassword akadmin
kubectl -n authentik exec -it <authentik-worker-pod> -c worker -- ak create_admin_group akadmin
```

Create a new Authentik API token in UI and save to:

- `authentik-terraform-repo/out/authentik-ci.token`

### 2) Authentik Terraform reconcile

```bash
bash authentik-terraform-repo/scripts/tf-init-garage.sh
set -a; source authentik-terraform-repo/out/garage-tfstate.env; set +a
terraform -chdir=authentik-terraform-repo state list
terraform -chdir=authentik-terraform-repo plan
terraform -chdir=authentik-terraform-repo apply
```

If stale state references pre-reset objects, remove/import as needed:

```bash
terraform -chdir=authentik-terraform-repo state rm <address>
./authentik-terraform-repo/scripts/import-existing.sh
```

### 3) Vault re-init and reconcile

```bash
kubectl -n vault exec platform-vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > vault-terraform-repo/out/vault-init.json
jq -r '.unseal_keys_b64[0]' vault-terraform-repo/out/vault-init.json | xargs -I{} kubectl -n vault exec platform-vault-0 -- vault operator unseal {}
jq -r '.root_token' vault-terraform-repo/out/vault-init.json > vault-terraform-repo/out/vault.token
```

Apply Vault Terraform:

```bash
bash vault-terraform-repo/scripts/tf-init-garage.sh
set -a; source vault-terraform-repo/out/garage-tfstate.env; source vault-terraform-repo/out/authentik.env; source vault-terraform-repo/out/democratic-csi.env; set +a
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(<vault-terraform-repo/out/vault.token)
terraform -chdir=vault-terraform-repo apply
```

### 4) External Secrets refresh

```bash
kubectl -n external-secrets rollout restart deploy
kubectl get secretstore,clustersecretstore -A
kubectl get externalsecret -A
```

### 5) Forgejo runner re-registration

Generate a fresh runner token and update Vault `kv/forgejo/runner`, then refresh `forgejo-runner-init` ExternalSecret and restart runner deployment.

Validation:

```bash
kubectl -n forgejo-runner get pods
kubectl -n forgejo-runner logs deploy/forgejo-runner -c runner --tail=50
```

### 6) Argo + repo mirror recovery

Ensure the following repos exist in Forgejo and have `main` pushed:

- `akadmin/talos-proxmox-bootstrap`
- `akadmin/talos-proxmox-platform`
- `akadmin/vault-terraform-repo`
- `akadmin/authentik-terraform-repo`

Then force refresh:

```bash
kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get applications
```

### 7) Longhorn decommission

Pre-check no usage:

```bash
kubectl get pvc -A -o json | jq -r '.items[] | select(.spec.storageClassName=="longhorn" or .spec.storageClassName=="longhorn-static") | [.metadata.namespace,.metadata.name] | @tsv'
kubectl get pv -o json | jq -r '.items[] | select(.spec.storageClassName=="longhorn" or .spec.storageClassName=="longhorn-static") | .metadata.name'
```

Cleanup done:

- Remove Longhorn from platform GitOps sources.
- Delete stale Longhorn admission webhooks.
- Clear remaining Longhorn CR finalizers.
- Delete `StorageClass/longhorn` and `StorageClass/longhorn-static`.

## Final Validation Checklist

- `kubectl -n argocd get applications` -> all expected apps `Synced/Healthy`
- `kubectl get storageclass` -> only `democratic-iscsi` remains default
- `kubectl get ns longhorn-system` -> not found
- Login works for Argo CD, Forgejo, Vault, Grafana via Authentik
- `kubectl get externalsecret -A` -> all `SecretSynced=True`

## Hardening Follow-ups

- Enforce one-at-a-time Terraform apply per repo/environment in Forgejo Actions concurrency groups.
- Store Vault init/unseal artifacts in secure offline storage and remove local transient copies.
- Keep this runbook updated when recovery procedures change.
