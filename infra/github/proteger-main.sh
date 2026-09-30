#!/usr/bin/env bash
# Protege a branch main do repositório no GitHub (requer GitHub CLI autenticado: gh auth login).
# Uso: infra/github/proteger-main.sh <dono>/<repositorio> [aprovacoes]
#   aprovacoes = revisões obrigatórias no PR (padrão 1; use 0 se o trabalho for individual)
#
# Regras:
#   - merge só por pull request, com N aprovações (revisão humana além do check);
#   - check do Jenkins obrigatório e branch atualizada com a main antes do merge;
#   - sem push direto nem force-push; vale também para administradores.
# O nome do check é o contexto publicado pelo GitHub Branch Source para PRs:
#   "continuous-integration/jenkins/pr-merge"
set -euo pipefail
REPO="${1:?informe dono/repositorio}"
APROVACOES="${2:-1}"

gh api --method PUT "repos/${REPO}/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["continuous-integration/jenkins/pr-merge"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": ${APROVACOES},
    "require_code_owner_reviews": false,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
echo "Branch main de ${REPO} protegida."
gh api "repos/${REPO}/branches/main/protection" --jq '{checks: .required_status_checks.contexts, reviews: .required_pull_request_reviews.required_approving_review_count, admins: .enforce_admins.enabled}'
