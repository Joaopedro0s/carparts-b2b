#!/usr/bin/env bash
# Coleta as evidências textuais do laboratório (sem segredos) em ~/out/evid.
# IDs de assinatura e do service principal são mascarados antes de gravar.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
O="$HOME/out/evid"; mkdir -p "$O"
G="env -u GITHUB_TOKEN gh"
REPO="$($G repo view --json nameWithOwner -q .nameWithOwner)"
J=http://127.0.0.1:8080
mask() { sed -E 's#/subscriptions/[0-9a-f-]{36}#/subscriptions/<assinatura>#g; s#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#<guid>#g'; }

# E1 · nós e isolamento do controller
~/jk.sh "$J/computer/api/json?tree=computer[displayName,numExecutors,offline,assignedLabels[name]]" \
  | python3 -c 'import json,sys
for c in json.load(sys.stdin)["computer"]:
    print("%-18s executores=%s offline=%s rotulos=%s" % (c["displayName"], c["numExecutors"], c["offline"], [l["name"] for l in c["assignedLabels"]]))' > "$O/E1-1-nos.txt"
{ echo '$ docker ps'; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo; echo '$ ss -ltn (portas do controller)'; ss -ltn | grep -E 'State|:8080 |:50000 '; } > "$O/E1-2-controller.txt"

# E2 · JCasC, autenticação e autorização
docker logs "$(docker ps -qf name=jenkins | head -1)" 2>&1 \
  | grep -E 'Configuration as Code|ConfigurationAsCode|fully up and running' | tail -8 > "$O/E2-1-jcasc.txt"
{ for p in /api/json /job/carparts-api/ /manage/ /signup; do
    curl -s -o /dev/null -w "anônimo GET $p -> HTTP %{http_code}\n" "$J$p"; done; } > "$O/E2-2-anonimo.txt"
~/jk.sh --data-urlencode 'script=def s = jenkins.model.Jenkins.get().authorizationStrategy
println "Estratégia: " + s.class.simpleName
s.getGrantedPermissionEntries().each { p, es -> println String.format("%-28s %s", p.group.title.toString() + "/" + p.name, es.collect { it.type.toString().toLowerCase() + ":" + it.sid }.sort()) }
println "Anonymous com alguma permissão: " + s.getGrantedPermissionEntries().values().flatten().any { it.sid == "anonymous" }
println "Executores do nó interno: " + jenkins.model.Jenkins.get().numExecutors' "$J/scriptText" > "$O/E2-3-matriz.txt"

# E3/E4 · pipeline, credenciais e deploys
~/jk.sh "$J/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName,description]" \
  | python3 -c 'import json,sys
for c in json.load(sys.stdin)["credentials"]: print("%-24s %-28s %s" % (c["id"], c["typeName"], c["description"]))' > "$O/E4-2-credenciais.txt"
ULT=$(~/jk.sh "$J/job/carparts-api/job/main/lastSuccessfulBuild/buildNumber")
~/jk.sh "$J/job/carparts-api/job/main/$ULT/consoleText" \
  | grep -E 'Imagem encontrada|Deploy em (hml|prd) concluído|Smoke test|Aprovação registrada|Trying to pass milestone|Lock acquired|Finished:' \
  | mask > "$O/E4-3-console-main-$ULT.txt"
{ for a in hml prd; do
    F=$(az containerapp show -n ca-carparts-api-$a -g rg-carparts-$a --query properties.configuration.ingress.fqdn -o tsv)
    echo "== $a: https://$F/health"; curl -s "https://$F/health"; echo; done; } > "$O/E4-4-health.txt"
{ SP=$(az ad sp list --display-name sp-jenkins-carparts --query '[0].appId' -o tsv)
  echo '$ az role assignment list --assignee <appId do sp-jenkins-carparts> --all'
  az role assignment list --assignee "$SP" --all --query '[].{papel:roleDefinitionName, escopo:scope}' -o table | mask
  echo; echo '$ az containerapp show (imagem em execução, por digest)'
  for a in hml prd; do az containerapp show -n ca-carparts-api-$a -g rg-carparts-$a \
    --query '{app:name, imagem:properties.template.containers[0].image, registro:properties.configuration.registries[0].username, estado:properties.runningStatus}' -o tsv; done
  echo; echo '$ az acr repository show-tags (últimas)'
  az acr repository show-tags -n acrcarparts26179863 --repository carparts-api --orderby time_desc --top 8 -o tsv
  echo; echo '$ orçamento'
  az rest --method get --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Consumption/budgets/orcamento-cicd-carparts?api-version=2023-05-01" \
    --query '{nome:name, valor:properties.amount, periodo:properties.timeGrain, alertas:keys(properties.notifications)}' -o json 2>&1 | mask
} > "$O/E4-1-azure.txt" 2>&1

# E5 · webhook e proteção da main
HOOK=$($G api "repos/$REPO/hooks" --jq '.[0].id')
$G api "repos/$REPO/hooks/$HOOK/deliveries?per_page=30" \
  --jq '.[] | [.delivered_at, .event, (.action // "-"), .status_code] | @tsv' > "$O/E5-1-entregas-webhook.txt"
tail -30 "$HOME/smee.log" | sed -E 's#https://smee.io/[A-Za-z0-9]+#https://smee.io/<canal>#' > "$O/E5-1-relay.txt"
$G api "repos/$REPO/branches/main/protection" --jq '{checks_obrigatorios: .required_status_checks.contexts, branch_atualizada: .required_status_checks.strict, revisoes: .required_pull_request_reviews.required_approving_review_count, admins_inclusos: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled, exclusao: .allow_deletions.enabled, conversas_resolvidas: .required_conversation_resolution.enabled}' > "$O/E5-4-protecao.json"
$G pr list --state all --limit 20 --json number,title,state,headRefName --jq '.[] | [.number, .state, .headRefName, .title] | @tsv' > "$O/E5-2-prs.txt"

# E6 · métricas (usuário admin só neste script; senha lida do arquivo de segredo, nunca impressa)
JENKINS_URL="$J/" JENKINS_USER=admin JENKINS_TOKEN="$(cat jenkins/controller/secrets/ADMIN_PASSWORD)" \
  python3 metrics/coletar_metricas.py --job carparts-api --baseline-dias 11 > "$O/E6-coleta.txt" 2>&1
cp metrics/saida/* "$O/" 2>/dev/null
ls -la "$O"
