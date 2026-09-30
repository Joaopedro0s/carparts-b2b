#!/usr/bin/env bash
# Sobe o controller (contêiner) e o agent ubuntu-agent-01 (processo no Codespace).
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
CTRL="$RAIZ/jenkins/controller"
cd "$CTRL"
./gerar-segredos.sh

# Token do GitHub para o Jenkins: vem do gh CLI (login feito pelo aluno) direto para o arquivo.
env -u GITHUB_TOKEN gh auth token | tr -d '\n' > secrets/GITHUB_TOKEN
env -u GITHUB_TOKEN gh api user --jq .login | tr -d '\n' > secrets/GITHUB_USER
chmod 600 secrets/*

cat > .env <<ENV
LAN_IP=127.0.0.1
JENKINS_URL=http://localhost:8080/
GITHUB_OWNER=$(cat secrets/GITHUB_USER)
ENV

docker compose up -d --build jenkins
echo "Aguardando o Jenkins subir..."
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/login)" = "200" ]; do sleep 5; done
docker compose logs jenkins 2>&1 | grep -iE "configuration as code|fully up|SEVERE" | tail -n 5 || true

# Agent: segredo do nó lido pela API (autenticada) e gravado em arquivo 600.
ADMIN_PW="$(cat secrets/ADMIN_PASSWORD)"
mkdir -p "$HOME/jenkins-agent"
curl -fsS -u "admin:$ADMIN_PW" http://127.0.0.1:8080/computer/ubuntu-agent-01/jenkins-agent.jnlp \
  | python3 -c 'import sys,re; print(re.findall(r"<argument>([0-9a-f]{64})</argument>", sys.stdin.read())[0], end="")' \
  > "$HOME/jenkins-agent/secret"
chmod 600 "$HOME/jenkins-agent/secret"
unset ADMIN_PW
curl -fsS http://127.0.0.1:8080/jnlpJars/agent.jar -o "$HOME/jenkins-agent/agent.jar"

export AZURE_EXTENSION_DIR="$HOME/az-extensions"
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
az extension add --name containerapp --upgrade --only-show-errors

pkill -f "jenkins-agent/agent.jar" || true
nohup java -jar "$HOME/jenkins-agent/agent.jar" -url http://localhost:8080/ -name ubuntu-agent-01 \
  -secret @"$HOME/jenkins-agent/secret" -workDir "$HOME/jenkins-agent" > "$HOME/jenkins-agent/agent.log" 2>&1 &
sleep 10
tail -n 3 "$HOME/jenkins-agent/agent.log"
echo
echo "Jenkins: aba PORTS do Codespace -> porta 8080 (privada)."
echo "Usuário admin, senha em: jenkins/controller/secrets/ADMIN_PASSWORD"
