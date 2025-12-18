#!/usr/bin/env bash
set -euo pipefail

# Quickly replace GitHub URLs with Forgejo URLs in ApplicationSet manifests.
# Example:
#   ./hack/set-repourl.sh https://github.com/YOUR_GH_USER/talos-platform.git https://forgejo.example/YOURORG/talos-platform.git

FROM=${1:?from}
TO=${2:?to}

grep -RIl "$FROM" clusters/ | xargs -r sed -i.bak "s|$FROM|$TO|g"
echo "Updated repoURL refs under clusters/. Review the .bak files, then commit."
