#!/usr/bin/env python3
"""Relay de webhook do laboratório: smee.io (SSE) -> Jenkins local.

Substitui o smee-client: repassa os cabeçalhos do GitHub (evento, entrega,
assinatura HMAC X-Hub-Signature-256) e o Content-Type, que o Jenkins exige.
Nenhuma porta do Jenkins é exposta: a conexão é de saída, do Codespace para o smee.io.

Uso: lab/relay-webhook.py <url-do-canal-smee> http://127.0.0.1:8080/github-webhook/
"""
import json
import sys
import time
import urllib.error
import urllib.request

ORIGEM, DESTINO = sys.argv[1], sys.argv[2]
REPASSAR = ("x-github-event", "x-github-delivery", "x-hub-signature", "x-hub-signature-256",
            "x-github-hook-id", "x-github-hook-installation-target-id",
            "x-github-hook-installation-target-type", "user-agent")


def repassar(evento):
    corpo = evento.pop("body", None)
    if corpo is None:
        return
    # mesma serialização do smee-client (JSON.stringify): sem espaços, UTF-8 sem escape
    dados = json.dumps(corpo, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    cab = {k: v for k, v in evento.items() if k.lower() in REPASSAR}
    cab["Content-Type"] = "application/json"
    req = urllib.request.Request(DESTINO, data=dados, headers=cab, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            codigo = r.status
    except urllib.error.HTTPError as e:
        codigo = e.code
    print(f"POST {evento.get('x-github-event')} -> {codigo}", flush=True)


while True:
    try:
        req = urllib.request.Request(ORIGEM, headers={"Accept": "text/event-stream"})
        with urllib.request.urlopen(req, timeout=120) as fluxo:
            print(f"Conectado a {ORIGEM}; repassando para {DESTINO}", flush=True)
            for bruta in fluxo:
                linha = bruta.decode("utf-8").rstrip("\n")
                if linha.startswith("data:"):
                    try:
                        repassar(json.loads(linha[5:]))
                    except (ValueError, AttributeError):
                        pass
    except Exception as erro:  # reconecta sempre (queda de rede, timeout do SSE)
        print(f"reconectando ({erro})", flush=True)
        time.sleep(3)
