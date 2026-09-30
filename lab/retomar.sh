#!/usr/bin/env bash
# Retoma o laboratório depois que o Codespace é reiniciado (stop/start).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# 1) Docker com DNS público: o DNS padrão do Codespace não resolve dentro de contêineres aninhados
if ! pgrep -af dockerd | grep -q 8.8.8.8; then
  sudo pkill dockerd; sleep 5
  sudo sh -c 'nohup dockerd --dns 8.8.8.8 --dns 1.1.1.1 > /tmp/dockerd.log 2>&1 &'
  sleep 10
fi

# 2) Controller (override do laboratório: rede do host, escutando só em 127.0.0.1)
(cd jenkins/controller && docker compose -f docker-compose.yml -f docker-compose.lab.yml up -d jenkins)
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/login)" = "200" ]; do sleep 5; done

# 3) Agent ubuntu-agent-01 (processo no próprio Codespace)
sudo mkdir -p /home/jenkins/agent && sudo chown -R "$(id -u):$(id -g)" /home/jenkins
export AZURE_EXTENSION_DIR="$HOME/az-extensions" AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
pkill -f "jenkins-agent/agent.jar" || true
nohup java -jar "$HOME/jenkins-agent/agent.jar" -url http://localhost:8080/ -name ubuntu-agent-01 \
  -secret @"$HOME/jenkins-agent/secret" -workDir /home/jenkins/agent > "$HOME/jenkins-agent/agent.log" 2>&1 &

# 4) Relay do webhook (se já configurado)
if [ -s "$HOME/.smee-url" ]; then
  pkill -f "smee-client|relay-webhook" || true
  nohup python3 "$(dirname "$0")/relay-webhook.py" "$(cat "$HOME/.smee-url")" http://127.0.0.1:8080/github-webhook/ > "$HOME/smee.log" 2>&1 &
fi
echo "Laboratório retomado."
