#!/usr/bin/env bash
# Cria o webhook do GitHub para o Jenkins (eventos push e pull_request).
# Uso: infra/github/criar-webhook.sh <dono>/<repositorio> <https://jenkins-publico/>
# O segredo HMAC é lido do arquivo de segredo do controller e não aparece na tela.
set -euo pipefail
REPO="${1:?informe dono/repositorio}"
URL="${2:?informe a URL pública do Jenkins}"
SEGREDO_ARQ="$(dirname "$0")/../../jenkins/controller/secrets/GITHUB_WEBHOOK_SECRET"
[ -s "$SEGREDO_ARQ" ] || { echo "Gere o segredo com jenkins/controller/gerar-segredos.sh" >&2; exit 1; }

python3 - "$URL" "$SEGREDO_ARQ" <<'PY' | gh api --method POST "repos/${REPO}/hooks" --input - --jq '{id: .id, url: .config.url, eventos: .events}'
import json, sys
url, arq = sys.argv[1], sys.argv[2]
print(json.dumps({
    "name": "web", "active": True, "events": ["push", "pull_request"],
    "config": {"url": url.rstrip('/') + "/github-webhook/", "content_type": "json",
               "secret": open(arq).read().strip(), "insecure_ssl": "0"}
}))
PY
