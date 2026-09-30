# E1 · Arquitetura Jenkins da Carparts

![Arquitetura](img/arquitetura.png)

```mermaid
flowchart LR
  subgraph GH[GitHub]
    R[repo carparts-b2b<br/>main protegida]
  end
  subgraph LAN[Rede interna Carparts]
    N[Nginx 443 TLS] --> C[Controller Jenkins 2.568.3 LTS<br/>0 executores · 8080 em 127.0.0.1]
    A1[ubuntu-agent-01<br/>Ubuntu 24.04 · 2 exec<br/>linux docker azure-cli] -- TCP 50000 --> C
    A2[wsl-agent-01<br/>Win11+WSL2 · 1 exec<br/>linux docker wsl] -- WSS 443 --> N
    A3[wsl-agent-02<br/>Win11+WSL2 · 1 exec<br/>linux docker wsl] -- WSS 443 --> N
  end
  subgraph AZ[Azure brazilsouth]
    ACR[(ACR Basic)]
    HML[Container App hml<br/>0-1 réplicas]
    PRD[Container App prd<br/>1-2 réplicas]
  end
  R -- webhook HMAC --> N
  C -- status no PR --> R
  A1 -- docker push / AcrPush --> ACR
  A1 -- az containerapp update --> HML
  A1 -- após aprovação --> PRD
  HML -. AcrPull .-> ACR
  PRD -. AcrPull .-> ACR
```

## Nós, executores, rótulos e portas

| Nó | Máquina / SO | Onde roda | Executores | Rótulos | Conexão |
|---|---|---|---|---|---|
| Controller (built-in) | ubuntu-01 · Ubuntu 24.04 | contêiner `jenkins/jenkins:2.568.3-lts-jdk21` (Compose) | **0** | `controller-nao-usar` | 8080 só em 127.0.0.1; Nginx 443 (LAN); 50000 (LAN) |
| ubuntu-agent-01 | ubuntu-02 · Ubuntu 24.04 | serviço systemd (agent.jar, Java 21) | 2 | `linux docker azure-cli` | inbound TCP 50000 |
| wsl-agent-01 | win-01 · Windows 11 + WSL 2 | Ubuntu 24.04 no WSL, systemd | 1 | `linux docker wsl` | inbound WebSocket 443 |
| wsl-agent-02 | win-02 · Windows 11 + WSL 2 | Ubuntu 24.04 no WSL, systemd | 1 | `linux docker wsl` | inbound WebSocket 443 |

## Decisão de hospedagem (resumo)

| Critério | A · Controller on-prem em Docker (**escolhido**) | B · Controller em VM Azure B2s | C · Jenkins no AKS |
|---|---|---|---|
| Restrição "ERP on-premises" | atende | exige VPN site-to-site até o ERP | exige VPN + cluster |
| Custo Azure/mês (estimado) | ~US$ 0 para o Jenkins | ~US$ 45-70 (VM + disco + IP + backup) | > US$ 150 (2 nós + LB) |
| Exposição | nada público além do webhook filtrado | IP público/Bastion a gerir | ingress público a gerir |
| Operação | equipe já usa Docker (Aula 02) | patches da VM | exige domínio de Kubernetes |
| Risco | máquina física única -> backup diário do volume | dependência de internet | complexidade |
