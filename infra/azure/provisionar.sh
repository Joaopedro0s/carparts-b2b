#!/usr/bin/env bash
# Provisiona a infraestrutura Azure da Carparts para CI/CD (executar UMA vez,
# por uma pessoa com permissão de Owner/User Access Administrator na assinatura,
# no Azure Cloud Shell ou com a Azure CLI local).
#
# Recursos (região em LOC; padrão brazilsouth):
#   rg-carparts-shared : ACR Basic (sem usuário admin)
#   rg-carparts-hml    : ambiente Container Apps + ca-carparts-api-hml (escala a zero)
#   rg-carparts-prd    : ambiente Container Apps + ca-carparts-api-prd (mín. 1 réplica)
#   sp-jenkins-carparts: service principal com ESCOPO MÍNIMO
#       - AcrPush somente no registro
#       - Contributor somente nos grupos rg-carparts-hml e rg-carparts-prd
#   Orçamento mensal de US$ 150 com alertas.
set -euo pipefail

LOC="${LOC:-brazilsouth}"   # Azure for Students pode restringir regiões: LOC=eastus ./provisionar.sh
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors
SUB_ID=$(az account show --query id --output tsv)
ACR_NAME="${ACR_NAME:-acrcarparts26179863}"   # nome global único (sufixo = RA)
RG_SHARED="rg-carparts-shared"
RG_HML="rg-carparts-hml"
RG_PRD="rg-carparts-prd"
TAGS="projeto=carparts-b2b dono=devops centro-custo=cicd"

echo ">> Provedores de recursos (assinaturas novas precisam registrar)"
for NS in Microsoft.ContainerRegistry Microsoft.App; do
  az provider register --namespace "$NS" --wait --output none
done

echo ">> Grupos de recursos"
for RG in "$RG_SHARED" "$RG_HML" "$RG_PRD"; do
  az group create --name "$RG" --location "$LOC" --tags $TAGS --output none
done

echo ">> Azure Container Registry (Basic, sem admin user)"
az acr show --name "$ACR_NAME" --output none 2>/dev/null || \
  az acr create --resource-group "$RG_SHARED" --name "$ACR_NAME" --sku Basic \
    --admin-enabled false --output none
ACR_ID=$(az acr show --name "$ACR_NAME" --query id --output tsv)

criar_ambiente() {
  local RG="$1" ENV_NAME="$2" APP_NAME="$3" MIN="$4" MAX="$5"
  echo ">> Ambiente $ENV_NAME e app $APP_NAME"
  # sem Log Analytics (custo): logs consultados com "az containerapp logs show"
  az containerapp env show --name "$ENV_NAME" --resource-group "$RG" --output none 2>/dev/null || \
    az containerapp env create --name "$ENV_NAME" --resource-group "$RG" --location "$LOC" \
      --logs-destination none --output none

  # imagem inicial pública; o Jenkins substitui pela imagem do ACR no primeiro deploy
  az containerapp show --name "$APP_NAME" --resource-group "$RG" --output none 2>/dev/null || \
  az containerapp create --name "$APP_NAME" --resource-group "$RG" --environment "$ENV_NAME" \
    --image mcr.microsoft.com/k8se/quickstart:latest \
    --target-port 80 --ingress external \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$MIN" --max-replicas "$MAX" \
    --system-assigned --output none

  # o app puxa do ACR com identidade gerenciada (AcrPull), sem senha
  local PRINCIPAL
  PRINCIPAL=$(az containerapp show -n "$APP_NAME" -g "$RG" --query identity.principalId -o tsv)
  az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role AcrPull --scope "$ACR_ID" --output none || true
  sleep 30   # propagação da atribuição de papel antes de configurar o registro
  az containerapp registry set -n "$APP_NAME" -g "$RG" \
    --server "${ACR_NAME}.azurecr.io" --identity system --output none
}

criar_ambiente "$RG_HML" cae-carparts-hml ca-carparts-api-hml 0 1
criar_ambiente "$RG_PRD" cae-carparts-prd ca-carparts-api-prd 1 2

echo ">> Service principal do Jenkins (escopo mínimo)"
# Contributor apenas nos dois grupos de aplicação
SP_JSON=$(az ad sp create-for-rbac --name sp-jenkins-carparts --role Contributor \
  --scopes "/subscriptions/$SUB_ID/resourceGroups/$RG_HML" \
           "/subscriptions/$SUB_ID/resourceGroups/$RG_PRD" \
  --years 1 --output json)
SP_APP_ID=$(echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')
# AcrPush apenas no registro (push da imagem e leitura do digest)
az role assignment create --assignee "$SP_APP_ID" --role AcrPush --scope "$ACR_ID" --output none || true

# Os valores sensíveis vão DIRETO para os arquivos de segredo do controller (fora do Git).
DEST="${SECRETS_DIR:-../../jenkins/controller/secrets}"
umask 077
echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"], end="")'    > "$DEST/AZURE_CLIENT_ID"
echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"], end="")' > "$DEST/AZURE_CLIENT_SECRET"
echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tenant"], end="")'   > "$DEST/AZURE_TENANT_ID"
printf '%s' "$SUB_ID" > "$DEST/AZURE_SUBSCRIPTION_ID"
unset SP_JSON
echo "Credenciais do service principal gravadas em $DEST (arquivos 600, ignorados pelo Git)."

echo ">> Orçamento de CI/CD: US\$ 150/mês"
az consumption budget create --budget-name orcamento-cicd-carparts \
  --amount 150 --category cost --time-grain monthly \
  --start-date "$(date +%Y-%m-01)" --end-date "$(date -d '+1 year' +%Y-%m-01)" \
  --output none || echo "Aviso: crie o orçamento pelo portal (Cost Management > Budgets)."
echo "Configure no portal os alertas do orçamento em 50%, 80% e 100% (e-mail da equipe)."

echo ">> Pronto. URLs:"
az containerapp show -n ca-carparts-api-hml -g "$RG_HML" --query properties.configuration.ingress.fqdn -o tsv
az containerapp show -n ca-carparts-api-prd -g "$RG_PRD" --query properties.configuration.ingress.fqdn -o tsv
