# secrets/

Pasta dos Docker secrets lidos pelo JCasC (`/run/secrets/<NOME>`).
**Todo o conteúdo desta pasta, exceto este README, é ignorado pelo Git.**

Gere com `../gerar-segredos.sh`. Arquivos esperados (um valor por arquivo, sem quebra de linha):

| Arquivo | Origem |
|---|---|
| ADMIN_PASSWORD, APROVADOR1_PASSWORD, APROVADOR2_PASSWORD, DEV01..04_PASSWORD, DESIGNER01_PASSWORD | gerar-segredos.sh |
| GITHUB_WEBHOOK_SECRET | gerar-segredos.sh (colar o mesmo valor no webhook do GitHub) |
| GITHUB_USER, GITHUB_TOKEN | token fine-grained do GitHub (Contents: read, Commit statuses: read/write, Pull requests: read, Webhooks: read) |
| AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID | infra/azure/provisionar.sh |
