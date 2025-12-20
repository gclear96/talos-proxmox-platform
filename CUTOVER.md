# Cutover: GitHub -> in-cluster Forgejo (platform repo)

This repo is intended to be mirrored into Forgejo once Forgejo is running in-cluster.

## One-time Forgejo prerequisites

- Decide your Forgejo base URL (example: `https://forgejo.example.com`).
- Ensure `clusters/homelab/bootstrap/applicationset-oci.yaml` `ingressHost` matches that hostname and DNS/hosts resolve it.
- Create a repo for this platform repo (example: `YOURORG/talos-platform`).
- Ensure Argo CD can reach Forgejo (network + DNS).

## Mirror the repo

From your local clone of this repo:

```bash
git remote add forgejo https://forgejo.example.com/YOURORG/talos-platform.git
git push --mirror forgejo
```

## Update repoURL references in-cluster

This repo contains Argo CD ApplicationSets that include explicit `repoURL` fields (for the generator and the rendered Applications).
Update them before you switch the bootstrap repo’s root app to Forgejo:

```bash
./hack/set-repourl.sh https://github.com/YOUR_GH_USER/talos-platform.git https://forgejo.example.com/YOURORG/talos-platform.git
git status
git commit -am "chore: repourl cutover to forgejo"
git push
git push --mirror forgejo
```

## Verify after cutover

Once the bootstrap repo is updated to point at Forgejo:

- `kubectl -n argocd get applicationsets`
- `kubectl -n argocd get applications`
