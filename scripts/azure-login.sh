#!/usr/bin/env bash
# Login na Azure com o service principal injetado pelo Jenkins (withCredentials).
# As variáveis chegam mascaradas; este script nunca as imprime.
set -euo pipefail

: "${AZURE_CLIENT_ID:?credencial azure-sp ausente}"
: "${AZURE_CLIENT_SECRET:?credencial azure-sp ausente}"
: "${AZURE_TENANT_ID:?credencial azure-tenant-id ausente}"
: "${AZURE_SUBSCRIPTION_ID:?credencial azure-subscription-id ausente}"

set +x   # garante que nenhum comando com segredo apareça no log
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --output none
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
echo "Login na Azure OK (assinatura selecionada)."
