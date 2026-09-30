# Laboratório no GitHub Codespaces

Ambiente usado para gerar as evidências reais da atividade. Um Codespace (Ubuntu 24.04,
4 vCPU) faz o papel das duas máquinas Linux do projeto:

| Papel no projeto | No laboratório |
|---|---|
| ubuntu-01 (controller) | contêiner `jenkins-carparts` (Docker Compose), 8080 só em 127.0.0.1 |
| ubuntu-02 (ubuntu-agent-01) | processo `agent.jar` no próprio Codespace, com Docker e Azure CLI |
| wsl-agent-01/02 | declarados no JCasC, ficam offline no laboratório |
| Nginx + webhook filtrado | relay `smee.io` → `127.0.0.1:8080/github-webhook/` (nenhuma porta aberta) |

A porta 8080 é encaminhada pelo Codespaces como **privada**: só abre para quem está
logado no GitHub como dono do Codespace.

## Ordem

```bash
unset GITHUB_TOKEN && gh auth login -h github.com -p https -s admin:repo_hook,repo -w   # login do aluno (device code)
az login --use-device-code                                                              # login do aluno (device code)
lab/00-azure.sh          # provisiona a Azure e grava as credenciais do SP em secrets/
lab/01-jenkins.sh        # gera segredos, sobe o controller e o agent
lab/02-github.sh         # webhook (smee) + proteção da main
lab/mudanca.sh <n>       # cria branch, commit, PR e faz merge quando o check ficar verde
python3 metrics/coletar_metricas.py   # E6
infra/azure/destruir.sh  # ao final
```
