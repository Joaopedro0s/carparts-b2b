# carparts-b2b · CI/CD com Jenkins e Azure (SAP1-DEVOPS)

API Node.js do portal de pedidos B2B da Carparts, com pipeline de CI/CD em Jenkins
(controller reprodutível por JCasC, builds só em agents) e homologação/produção no
Azure Container Apps.

Autor: **Joao Pedro Fonseca** · RA 26179863 · ADS · UNISENAI Taubaté

## Estrutura

| Caminho | Entregável | Conteúdo |
|---|---|---|
| `docs/arquitetura.md` | E1 | diagrama e decisões de arquitetura |
| `jenkins/controller/` | E2 | Dockerfile, plugins.txt, casc.yaml, docker-compose, Nginx |
| `jenkins/agents/` | E1/E2 | instalação dos agents (Ubuntu 24.04 e WSL 2) |
| `Jenkinsfile` | E3 | pipeline declarativo de CI/CD |
| `scripts/` | E3/E4 | login Azure, deploy, smoke test, registro de deploy, rollback |
| `infra/azure/` | E4 | provisionamento (ACR, Container Apps, SP de escopo mínimo, orçamento) |
| `infra/github/` | E5 | webhook e proteção da branch main |
| `metrics/` | E6 | coleta das métricas DORA pela API do Jenkins |
| `src/`, `test/` | - | API e testes (node:test com relatório JUnit) |

## Passo a passo (ordem de execução)

1. **API local**: `npm ci && npm run lint && npm test` (gera `reports/junit.xml`).
2. **Segredos**: `jenkins/controller/gerar-segredos.sh`; preencher `GITHUB_USER` e `GITHUB_TOKEN`.
3. **Azure**: `cd infra/azure && ./provisionar.sh` (grava as credenciais do SP direto em `jenkins/controller/secrets/`).
4. **Controller**: `cd jenkins/controller && cp .env.example .env` (ajustar) e `docker compose up -d --build`.
   Certificado TLS em `jenkins/controller/nginx/certs/jenkins.crt|key` (CA interna ou autoassinado no laboratório).
5. **Agents**: em cada máquina, `sudo jenkins/agents/instalar-agent-ubuntu.sh <nó> <url> [websocket]`.
6. **GitHub**: `infra/github/criar-webhook.sh dono/carparts-b2b https://<url-publica>/` e
   `infra/github/proteger-main.sh dono/carparts-b2b [aprovacoes]`.
7. **Execuções**: abrir PRs, fazer merge na main e aprovar em produção até somar 10+ execuções.
8. **Métricas**: `JENKINS_URL=... JENKINS_USER=... JENKINS_TOKEN=... python3 metrics/coletar_metricas.py`.
9. **Fim do laboratório**: `infra/azure/destruir.sh` para não gerar custo.

Laboratório sem URL pública: use um relay de webhook (ex.: `smee.io` + `smee-client` apontando para
`http://127.0.0.1:8080/github-webhook/`) em vez de abrir portas; ou, temporariamente,
`triggers { pollSCM('H/5 * * * *') }`.

## Regras que não podem ser quebradas

- Nenhum segredo no Git: `jenkins/controller/secrets/*`, `.env` e `*.key` estão no `.gitignore`.
- Nó interno com `numExecutors: 0`; o Jenkinsfile usa `agent none` e cada stage pede um rótulo.
- Porta 8080 publicada só em `127.0.0.1`; acesso pelo Nginx (HTTPS, LAN/VPN).
- Produção só depois do `input` com `submitter` restrito; deploy por **digest** da imagem publicada.
