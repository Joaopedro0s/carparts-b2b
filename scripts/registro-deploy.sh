#!/usr/bin/env bash
# Gera o registro de rastreabilidade de um deploy em produção (JSON, arquivado pelo Jenkins).
# É a matéria-prima das métricas DORA (lead time e frequência de implantação).
set -euo pipefail

HEAD_COMMIT="${GIT_COMMIT:-$(git rev-parse HEAD)}"

# Commit mais antigo incluído nesta entrega (desde o último build de sucesso da main)
if [ -n "${GIT_PREVIOUS_SUCCESSFUL_COMMIT:-}" ] && git cat-file -e "${GIT_PREVIOUS_SUCCESSFUL_COMMIT}^{commit}" 2>/dev/null; then
  PRIMEIRO_COMMIT_EM=$(git log --format=%cI "${GIT_PREVIOUS_SUCCESSFUL_COMMIT}..${HEAD_COMMIT}" | tail -n 1)
fi
PRIMEIRO_COMMIT_EM="${PRIMEIRO_COMMIT_EM:-$(git show -s --format=%cI "$HEAD_COMMIT")}"

if [ -n "${APROVADO_EM_MS:-}" ]; then
  APROVADO_EM=$(date -d "@$((APROVADO_EM_MS / 1000))" --iso-8601=seconds)
else
  APROVADO_EM=""
fi

cat <<JSON
{
  "app": "${APP:-carparts-api}",
  "build": ${BUILD_NUMBER:-0},
  "branch": "${BRANCH_NAME:-main}",
  "commit": "${HEAD_COMMIT}",
  "primeiro_commit_em": "${PRIMEIRO_COMMIT_EM}",
  "imagem_tag": "${IMAGE_TAG:-}",
  "imagem_digest": "${IMAGE_DIGEST:-}",
  "aprovado_por": "${APROVADO_POR:-}",
  "aprovado_em": "${APROVADO_EM}",
  "deploy_producao_em": "$(date --iso-8601=seconds)"
}
JSON
