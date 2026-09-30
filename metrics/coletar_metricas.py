#!/usr/bin/env python3
"""Coleta métricas de entrega (DORA) a partir da API REST do Jenkins.

Uso:
    export JENKINS_URL=https://jenkins.carparts.local/
    export JENKINS_USER=dev01
    export JENKINS_TOKEN=<API token do usuário>   # nunca versionar
    python3 metrics/coletar_metricas.py --job carparts-api --baseline-dias 11

Saídas (pasta metrics/saida/, ignorada pelo Git):
    execucoes.csv  - uma linha por execução (todas as branches e PRs)
    deploys.csv    - uma linha por deploy em produção (deploy-record.json)
    resumo.md      - tabela pronta para colar no relatório (E6)
"""
import argparse
import base64
import csv
import json
import os
import ssl
import statistics
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def api(base, caminho, user, token, contexto):
    url = urllib.parse.urljoin(base, caminho)
    req = urllib.request.Request(url)
    cred = base64.b64encode(f"{user}:{token}".encode()).decode()
    req.add_header("Authorization", f"Basic {cred}")
    with urllib.request.urlopen(req, context=contexto, timeout=30) as resp:
        return json.loads(resp.read().decode())


def iso(ms):
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat()


def horas(delta):
    return round(delta.total_seconds() / 3600, 2)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--job", default="carparts-api")
    p.add_argument("--baseline-dias", type=float, default=11.0)
    p.add_argument("--max-builds", type=int, default=100)
    p.add_argument("--ca", help="certificado da CA interna (se o Jenkins usa certificado próprio)")
    a = p.parse_args()

    base = os.environ.get("JENKINS_URL")
    user = os.environ.get("JENKINS_USER")
    token = os.environ.get("JENKINS_TOKEN")
    if not (base and user and token):
        sys.exit("Defina JENKINS_URL, JENKINS_USER e JENKINS_TOKEN no ambiente.")
    contexto = ssl.create_default_context(cafile=a.ca) if a.ca else ssl.create_default_context()

    arvore = f"jobs[name,url,builds[number,result,timestamp,duration,url]{{0,{a.max_builds}}}]"
    pasta = api(base, f"job/{a.job}/api/json?tree={urllib.parse.quote(arvore)}", user, token, contexto)

    execucoes, deploys = [], []
    for ramo in pasta.get("jobs", []):
        for b in ramo.get("builds", []):
            if b.get("result") is None:        # em andamento
                continue
            execucoes.append({
                "branch": urllib.parse.unquote(ramo["name"]),
                "build": b["number"],
                "resultado": b["result"],
                "inicio_utc": iso(b["timestamp"]),
                "duracao_min": round(b["duration"] / 60000, 2),
            })
            if ramo["name"] == "main" and b["result"] == "SUCCESS":
                try:
                    reg = api(b["url"], "artifact/deploy-record.json", user, token, contexto)
                except Exception:
                    continue
                inicio = datetime.fromisoformat(reg["primeiro_commit_em"])
                fim = datetime.fromisoformat(reg["deploy_producao_em"])
                reg["lead_time_h"] = horas(fim - inicio)
                deploys.append(reg)

    if not execucoes:
        sys.exit("Nenhuma execução concluída encontrada.")

    saida = Path(__file__).parent / "saida"
    saida.mkdir(exist_ok=True)
    with open(saida / "execucoes.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(execucoes[0].keys()))
        w.writeheader()
        w.writerows(sorted(execucoes, key=lambda e: e["inicio_utc"]))
    if deploys:
        with open(saida / "deploys.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(deploys[0].keys()))
            w.writeheader()
            w.writerows(deploys)

    total = len(execucoes)
    falhas = sum(1 for e in execucoes if e["resultado"] in ("FAILURE", "UNSTABLE"))
    abortadas = sum(1 for e in execucoes if e["resultado"] == "ABORTED")
    duracoes = [e["duracao_min"] for e in execucoes if e["resultado"] == "SUCCESS"]
    inicios = sorted(datetime.fromisoformat(e["inicio_utc"]) for e in execucoes)
    periodo_dias = max((inicios[-1] - inicios[0]).total_seconds() / 86400, 1)

    main_exec = [e for e in execucoes if e["branch"] == "main"]
    main_falhas = sum(1 for e in main_exec if e["resultado"] in ("FAILURE", "UNSTABLE"))

    linhas = [
        "| Métrica | Valor medido | Linha de base | Meta |",
        "|---|---|---|---|",
        f"| Execuções analisadas | {total} (período de {periodo_dias:.1f} dias) | builds manuais | mín. 10 |",
        f"| Taxa de falha do pipeline (todas as branches) | {falhas / total:.0%} ({falhas}/{total}) | não medida | < 15% |",
        f"| Taxa de falha na main | {(main_falhas / len(main_exec)) if main_exec else 0:.0%} | não medida | < 15% |",
        f"| Execuções abortadas/sem aprovação | {abortadas} | - | - |",
        f"| Duração mediana de um build com sucesso | {statistics.median(duracoes) if duracoes else 0:.1f} min | - | < 15 min |",
        f"| Deploys em produção | {len(deploys)} | - | - |",
        f"| Frequência de implantação | {len(deploys) / periodo_dias * 7:.1f} por semana | ~1 a cada 11 dias | >= 3 por semana |",
    ]
    if deploys:
        lts = sorted(d["lead_time_h"] for d in deploys)
        med = statistics.median(lts)
        p90 = lts[min(len(lts) - 1, int(round(0.9 * (len(lts) - 1))))]
        base_h = a.baseline_dias * 24
        linhas += [
            f"| Lead time mediano (commit -> produção) | {med:.1f} h ({med / 24:.2f} dias) | {a.baseline_dias:.0f} dias | <= 2 dias |",
            f"| Lead time p90 | {p90:.1f} h ({p90 / 24:.2f} dias) | {a.baseline_dias:.0f} dias | <= 2 dias |",
            f"| Redução do lead time vs. linha de base | {(1 - med / base_h):.0%} | - | >= 82% |",
        ]
    (saida / "resumo.md").write_text("\n".join(linhas) + "\n", encoding="utf-8")
    print("\n".join(linhas))
    print(f"\nArquivos gerados em {saida}")


if __name__ == "__main__":
    main()
