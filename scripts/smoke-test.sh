#!/usr/bin/env bash
# Smoke test pós-deploy.
# Uso: scripts/smoke-test.sh <url-base> <commit-esperado>
# Verifica: /health responde 200, o commit em execução é o esperado e o catálogo responde.
set -euo pipefail

URL="${1:?informe a URL base}"
COMMIT_ESPERADO="${2:?informe o commit esperado}"

echo "Smoke test em $URL"

# Container Apps pode levar alguns segundos para ativar a nova revisão
for tentativa in $(seq 1 12); do
  if CORPO=$(curl --silent --show-error --fail --max-time 10 "$URL/health"); then
    if echo "$CORPO" | grep -q "\"commit\":\"$COMMIT_ESPERADO\""; then
      echo "OK /health (tentativa $tentativa): $CORPO"
      break
    fi
    echo "Tentativa $tentativa: revisão antiga ainda ativa ($CORPO)"
  else
    echo "Tentativa $tentativa: /health ainda indisponível"
  fi
  if [ "$tentativa" -eq 12 ]; then
    echo "FALHA: a versão $COMMIT_ESPERADO não ficou saudável em $URL" >&2
    exit 1
  fi
  sleep 10
done

STATUS=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "$URL/api/pecas")
if [ "$STATUS" != "200" ]; then
  echo "FALHA: GET /api/pecas respondeu $STATUS" >&2
  exit 1
fi
echo "OK /api/pecas (200). Smoke test aprovado."
