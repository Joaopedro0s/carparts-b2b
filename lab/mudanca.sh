#!/usr/bin/env bash
# Gera uma mudança real no portal (branch + commit + PR) para exercitar o pipeline.
# Uso: lab/mudanca.sh <1-6> [--sem-merge]
#   1 listar pedidos · 2 buscar pedido por id · 3 desconto por volume
#   4 limite de itens (commit com teste errado: check vermelho) · 5 correção do teste do item 4
#   6 uptime no /health
# Sem --sem-merge, espera o check do Jenkins ficar verde e faz o merge (squash) na main.
set -euo pipefail
cd "$(dirname "$0")/.."
N="${1:?informe o número da mudança}"
MERGE=1; [ "${2:-}" = "--sem-merge" ] && MERGE=0
GH="env -u GITHUB_TOKEN gh"

case "$N" in
  1) BR="feature/listar-pedidos";      MSG="feat: GET /api/pedidos lista os pedidos" ;;
  2) BR="feature/buscar-pedido";       MSG="feat: GET /api/pedidos/:id" ;;
  3) BR="feature/desconto-volume";     MSG="feat: desconto de 5% para item com 100+ unidades" ;;
  4) BR="feature/limite-itens";        MSG="feat: limita o pedido a 20 itens" ;;
  5) BR="feature/limite-itens";        MSG="test: corrige expectativa do limite de itens" ;;
  6) BR="feature/health-uptime";       MSG="feat: /health informa uptime" ;;
  *) echo "mudança inválida" >&2; exit 2 ;;
esac

if [ "$N" != "5" ]; then
  git checkout main && git pull --ff-only
  git checkout -b "$BR"
else
  git checkout "$BR"
fi

python3 - "$N" <<'PY'
import sys, re
n = sys.argv[1]
app = open('src/app.js', encoding='utf-8').read()
tst = open('test/app.test.js', encoding='utf-8').read()
ROTA_404 = "  return enviarJson(res, 404, { erro: 'rota não encontrada' });"

if n == '1':
    app = app.replace(ROTA_404, """  if (req.method === 'GET' && url.pathname === '/api/pedidos') {
    return enviarJson(res, 200, pedidos);
  }

""" + ROTA_404)
    tst = tst.rstrip()[:-3] + """
  test('GET /api/pedidos lista os pedidos criados', async () => {
    const r = await fetch(`${base}/api/pedidos`);
    assert.equal(r.status, 200);
    assert.ok(Array.isArray(await r.json()));
  });
});
"""
elif n == '2':
    app = app.replace(ROTA_404, """  const matchPedido = url.pathname.match(/^\\/api\\/pedidos\\/(\\d+)$/);
  if (req.method === 'GET' && matchPedido) {
    const pedido = pedidos.find((p) => p.id === Number(matchPedido[1]));
    return pedido ? enviarJson(res, 200, pedido) : enviarJson(res, 404, { erro: 'pedido não encontrado' });
  }

""" + ROTA_404)
    tst = tst.rstrip()[:-3] + """
  test('GET /api/pedidos/:id inexistente responde 404', async () => {
    const r = await fetch(`${base}/api/pedidos/99999`);
    assert.equal(r.status, 404);
  });
});
"""
elif n == '3':
    app = app.replace("    return soma + peca.preco * item.quantidade;",
                      "    const desconto = item.quantidade >= 100 ? 0.95 : 1; // 5% para 100+ unidades\n    return soma + peca.preco * item.quantidade * desconto;")
    tst = tst.replace("describe('API HTTP', () => {", """describe('desconto por volume', () => {
  test('100 unidades recebem 5% de desconto', () => {
    assert.equal(calcularTotal([{ codigo: 'CP-2040', quantidade: 100 }]), 2327.5);
  });
});

describe('API HTTP', () => {""")
elif n == '4':
    app = app.replace("  if (!Array.isArray(pedido.itens) || pedido.itens.length === 0) {",
                      "  if (Array.isArray(pedido.itens) && pedido.itens.length > 20) {\n    erros.push('máximo de 20 itens por pedido');\n  }\n  if (!Array.isArray(pedido.itens) || pedido.itens.length === 0) {")
    tst = tst.replace("describe('API HTTP', () => {", """describe('limite de itens', () => {
  test('pedido com 21 itens é rejeitado', () => {
    const itens = Array.from({ length: 21 }, () => ({ codigo: 'CP-2040', quantidade: 1 }));
    assert.ok(validarPedido({ cliente: 'X', itens }).includes('máximo de 30 itens por pedido'));
  });
});

describe('API HTTP', () => {""")
elif n == '5':
    tst = tst.replace("máximo de 30 itens por pedido", "máximo de 20 itens por pedido")
elif n == '6':
    app = app.replace("return enviarJson(res, 200, { status: 'ok', versao: VERSION, commit: COMMIT, ambiente: AMBIENTE });",
                      "return enviarJson(res, 200, {\n      status: 'ok', versao: VERSION, commit: COMMIT, ambiente: AMBIENTE,\n      uptime_s: Math.round(process.uptime())\n    });")
    tst = tst.replace("    assert.equal(corpo.status, 'ok');", "    assert.equal(corpo.status, 'ok');\n    assert.equal(typeof corpo.uptime_s, 'number');")

open('src/app.js', 'w', encoding='utf-8').write(app)
open('test/app.test.js', 'w', encoding='utf-8').write(tst)
PY

git add src test
git commit -m "$MSG"
git push -u origin "$BR"

if [ "$N" != "5" ]; then
  $GH pr create --base main --head "$BR" --title "$MSG" \
    --body "Mudança gerada no laboratório SAP1-DEVOPS. O check do Jenkins (continuous-integration/jenkins/pr-merge) precisa estar verde para o merge."
fi

[ "$MERGE" = "1" ] || exit 0
echo "Aguardando o check do Jenkins no PR..."
sleep 20
$GH pr checks "$BR" --watch --interval 15 || { echo "Check vermelho: o merge está bloqueado pela proteção da main."; exit 1; }
$GH pr merge "$BR" --squash --delete-branch
git checkout main && git pull --ff-only
echo "Merge feito: acompanhe o build da main no Jenkins (vai pedir aprovação de produção)."
