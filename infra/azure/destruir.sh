#!/usr/bin/env bash
# Remove toda a infraestrutura de laboratório (evita custo após a avaliação).
set -euo pipefail
for RG in rg-carparts-hml rg-carparts-prd rg-carparts-shared; do
  az group delete --name "$RG" --yes --no-wait
done
APP_ID=$(az ad sp list --display-name sp-jenkins-carparts --query "[0].appId" -o tsv)
[ -n "$APP_ID" ] && az ad sp delete --id "$APP_ID"
echo "Exclusão solicitada. Acompanhe em: az group list -o table"
