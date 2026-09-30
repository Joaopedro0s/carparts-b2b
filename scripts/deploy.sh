#!/usr/bin/env bash
# Implanta a imagem JÁ PUBLICADA no ACR em um ambiente do Azure Container Apps.
# Uso: scripts/deploy.sh <hml|prd> <digest sha256:...> <tag>
# A imagem é referenciada pelo DIGEST: o mesmo artefato testado em homologação
# é o que vai para produção (nada é recompilado).
set -euo pipefail

AMBIENTE="${1:?informe hml ou prd}"
DIGEST="${2:?informe o digest da imagem}"
TAG="${3:?informe a tag da imagem}"
ACR_NAME="${ACR_NAME:-acrcarparts26179863}"
APP="${APP:-carparts-api}"

case "$AMBIENTE" in
  hml) RG="rg-carparts-hml"; CONTAINER_APP="ca-carparts-api-hml" ;;
  prd) RG="rg-carparts-prd"; CONTAINER_APP="ca-carparts-api-prd" ;;
  *)   echo "Ambiente inválido: $AMBIENTE" >&2; exit 2 ;;
esac

IMAGEM="${ACR_NAME}.azurecr.io/${APP}@${DIGEST}"

# 1) a imagem precisa existir no registro (garante promoção, não rebuild)
az acr repository show --name "$ACR_NAME" --image "${APP}@${DIGEST}" --output none
echo "Imagem encontrada no ACR: $IMAGEM (tag $TAG)"

# 2) guarda a imagem atual para rollback
ANTERIOR=$(az containerapp show --name "$CONTAINER_APP" --resource-group "$RG" \
  --query "properties.template.containers[0].image" --output tsv)
echo "Imagem anterior em $AMBIENTE: $ANTERIOR"
echo "$ANTERIOR" > ".imagem-anterior-$AMBIENTE"

# 3) a aplicação escuta na porta 3000 (o app nasce com a imagem de exemplo na porta 80)
PORTA=$(az containerapp show --name "$CONTAINER_APP" --resource-group "$RG" \
  --query "properties.configuration.ingress.targetPort" --output tsv)
if [ "$PORTA" != "3000" ]; then
  az containerapp ingress update --name "$CONTAINER_APP" --resource-group "$RG" --target-port 3000 --output none
fi

# 4) atualiza o Container App (nova revisão) com rastreabilidade nas tags
az containerapp update \
  --name "$CONTAINER_APP" \
  --resource-group "$RG" \
  --image "$IMAGEM" \
  --set-env-vars "AMBIENTE=$AMBIENTE" \
  --tags "build=${BUILD_NUMBER:-manual}" "commit=${GIT_COMMIT:-desconhecido}" \
         "imagem-tag=$TAG" "aprovado-por=${APROVADO_POR:-n/a}" \
  --output none

# 5) URL pública do ambiente para o smoke test
FQDN=$(az containerapp show --name "$CONTAINER_APP" --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" --output tsv)
echo "https://${FQDN}" > ".deploy-url-$AMBIENTE"
echo "Deploy em $AMBIENTE concluído: https://${FQDN}"
