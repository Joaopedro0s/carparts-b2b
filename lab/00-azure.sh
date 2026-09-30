#!/usr/bin/env bash
# Provisiona a Azure a partir do Codespace (depois de "az login --use-device-code").
set -euo pipefail
cd "$(dirname "$0")/.."
az account show --query "{assinatura:name, usuario:user.name}" -o table
( cd jenkins/controller && ./gerar-segredos.sh )
( cd infra/azure && SECRETS_DIR="$PWD/../../jenkins/controller/secrets" ./provisionar.sh )
