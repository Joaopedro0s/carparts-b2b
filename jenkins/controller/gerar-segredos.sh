#!/usr/bin/env bash
# Gera senhas aleatórias dos usuários do Jenkins e cria os arquivos de segredo vazios
# que precisam ser preenchidos à mão (GitHub) ou pelo infra/azure/provisionar.sh (Azure).
# Os arquivos ficam em ./secrets com permissão 600 e são ignorados pelo Git.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p secrets
umask 077

for U in ADMIN APROVADOR1 APROVADOR2 DEV01 DEV02 DEV03 DEV04 DESIGNER01; do
  F="secrets/${U}_PASSWORD"
  [ -s "$F" ] || openssl rand -base64 24 | tr -d '\n' > "$F"
done
[ -s secrets/GITHUB_WEBHOOK_SECRET ] || openssl rand -hex 32 | tr -d '\n' > secrets/GITHUB_WEBHOOK_SECRET

for F in AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID GITHUB_USER GITHUB_TOKEN; do
  [ -e "secrets/$F" ] || : > "secrets/$F"
done

echo "Segredos gerados em $(pwd)/secrets. Preencha GITHUB_USER e GITHUB_TOKEN;"
echo "os AZURE_* são gravados pelo infra/azure/provisionar.sh."
echo "Entregue cada senha ao respectivo usuário por canal seguro (nunca por chat/e-mail em texto)."
