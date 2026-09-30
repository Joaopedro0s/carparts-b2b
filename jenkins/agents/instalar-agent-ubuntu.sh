#!/usr/bin/env bash
# Instala um agent Jenkins como serviço systemd em Ubuntu 24.04
# (máquina ubuntu-02 ou Ubuntu dentro do WSL 2 das estações Windows 11).
#
# Uso (como root):
#   sudo ./instalar-agent-ubuntu.sh <nome-do-no> <jenkins-url> [websocket]
#   ex.: sudo ./instalar-agent-ubuntu.sh ubuntu-agent-01 https://jenkins.carparts.local/
#        sudo ./instalar-agent-ubuntu.sh wsl-agent-01    https://jenkins.carparts.local/ websocket
# O segredo do nó (Manage Jenkins > Nodes > <nó>) é pedido de forma interativa e
# gravado em /etc/jenkins-agent/secret (600). Ele nunca vai para o repositório.
# No WSL 2, habilite o systemd em /etc/wsl.conf ([boot] systemd=true).
set -euo pipefail

NOME="${1:?nome do nó}"
URL="${2:?URL do Jenkins}"
MODO="${3:-tcp}"

apt-get update
apt-get install -y openjdk-21-jre-headless curl git ca-certificates gnupg

# Docker Engine (repositório oficial)
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Azure CLI (script oficial da Microsoft para Debian/Ubuntu)
command -v az >/dev/null || curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Extensão containerapp da Azure CLI instalada uma vez, fora do AZURE_CONFIG_DIR de cada build
install -d /opt/az-extensions
AZURE_EXTENSION_DIR=/opt/az-extensions az extension add --name containerapp --upgrade --only-show-errors
chmod -R a+rX /opt/az-extensions

# Usuário de serviço sem login interativo
id jenkins >/dev/null 2>&1 || useradd --create-home --shell /bin/bash jenkins
usermod -aG docker jenkins
install -d -o jenkins -g jenkins /home/jenkins/agent

# agent.jar baixado do próprio controller (mesma versão do remoting)
curl -fsSL "${URL%/}/jnlpJars/agent.jar" -o /home/jenkins/agent.jar
chown jenkins:jenkins /home/jenkins/agent.jar

install -d -m 700 -o jenkins -g jenkins /etc/jenkins-agent
read -r -s -p "Cole o segredo do nó $NOME: " SEGREDO; echo
printf '%s' "$SEGREDO" > /etc/jenkins-agent/secret
chown jenkins:jenkins /etc/jenkins-agent/secret
chmod 600 /etc/jenkins-agent/secret
unset SEGREDO

EXTRA=""
[ "$MODO" = "websocket" ] && EXTRA="-webSocket"

cat > /etc/systemd/system/jenkins-agent.service <<UNIT
[Unit]
Description=Jenkins agent ${NOME}
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=jenkins
WorkingDirectory=/home/jenkins
Environment=AZURE_EXTENSION_DIR=/opt/az-extensions
Environment=AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
ExecStart=/usr/bin/java -jar /home/jenkins/agent.jar -url ${URL} -name ${NOME} -secret @/etc/jenkins-agent/secret -workDir /home/jenkins/agent ${EXTRA}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now jenkins-agent
systemctl --no-pager status jenkins-agent | head -n 5
echo "Agent $NOME instalado. Confira em Manage Jenkins > Nodes."
