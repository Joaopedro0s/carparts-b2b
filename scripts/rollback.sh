#!/usr/bin/env bash
# Rollback: volta um ambiente para uma imagem já publicada (sem rebuild).
# Uso: scripts/rollback.sh <hml|prd> <imagem-completa-anterior>
#   ex.: scripts/rollback.sh prd acrcarparts26179863.azurecr.io/carparts-api@sha256:abc...
# Alternativa: reativar a revisão anterior do Container App:
#   az containerapp revision list -n ca-carparts-api-prd -g rg-carparts-prd -o table
#   az containerapp revision activate -n ca-carparts-api-prd -g rg-carparts-prd --revision <nome>
set -euo pipefail

AMBIENTE="${1:?informe hml ou prd}"
IMAGEM="${2:?informe a imagem anterior (registro/repositorio@digest)}"

case "$AMBIENTE" in
  hml) RG="rg-carparts-hml"; CONTAINER_APP="ca-carparts-api-hml" ;;
  prd) RG="rg-carparts-prd"; CONTAINER_APP="ca-carparts-api-prd" ;;
  *)   echo "Ambiente inválido: $AMBIENTE" >&2; exit 2 ;;
esac

az containerapp update --name "$CONTAINER_APP" --resource-group "$RG" \
  --image "$IMAGEM" --tags "rollback=$(date --iso-8601=seconds)" --output none
echo "Rollback de $AMBIENTE para $IMAGEM concluído."
