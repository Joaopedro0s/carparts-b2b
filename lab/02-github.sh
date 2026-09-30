#!/usr/bin/env bash
# Webhook via relay smee.io (nenhuma porta do Jenkins exposta) + proteção da branch main.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(env -u GITHUB_TOKEN gh repo view --json nameWithOwner -q .nameWithOwner)"
SMEE="$(curl -Ls -o /dev/null -w '%{url_effective}' https://smee.io/new)"
echo "$SMEE" > "$HOME/.smee-url"
pkill -f smee-client || true
nohup npx -y smee-client --url "$SMEE" --target http://127.0.0.1:8080/github-webhook/ > "$HOME/smee.log" 2>&1 &

python3 - "$SMEE" "$RAIZ/jenkins/controller/secrets/GITHUB_WEBHOOK_SECRET" <<'PY' \
  | env -u GITHUB_TOKEN gh api --method POST "repos/${REPO}/hooks" --input - --jq '{id: .id, eventos: .events, ativo: .active}'
import json, sys
url, arq = sys.argv[1], sys.argv[2]
print(json.dumps({"name": "web", "active": True, "events": ["push", "pull_request"],
                  "config": {"url": url, "content_type": "json",
                             "secret": open(arq).read().strip(), "insecure_ssl": "0"}}))
PY
echo "Webhook criado (relay $SMEE)."
env -u GITHUB_TOKEN bash -c "'$RAIZ/infra/github/proteger-main.sh' '$REPO' 0"
