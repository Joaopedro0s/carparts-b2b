'use strict';

const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { criarServidor, validarPedido, calcularTotal } = require('../src/app');

let servidor;
let base;

before(async () => {
  servidor = criarServidor();
  await new Promise((resolve) => servidor.listen(0, resolve));
  base = `http://127.0.0.1:${servidor.address().port}`;
});

after(() => new Promise((resolve) => servidor.close(resolve)));

describe('regras de negócio', () => {
  test('pedido válido não gera erros', () => {
    assert.deepEqual(validarPedido({ cliente: 'Montadora X', itens: [{ codigo: 'CP-1001', quantidade: 2 }] }), []);
  });

  test('pedido sem cliente é rejeitado', () => {
    assert.ok(validarPedido({ itens: [{ codigo: 'CP-1001', quantidade: 1 }] }).includes('cliente é obrigatório'));
  });

  test('peça inexistente é rejeitada', () => {
    const erros = validarPedido({ cliente: 'X', itens: [{ codigo: 'CP-9999', quantidade: 1 }] });
    assert.match(erros[0], /não existe/);
  });

  test('quantidade acima do estoque é rejeitada', () => {
    const erros = validarPedido({ cliente: 'X', itens: [{ codigo: 'CP-3310', quantidade: 999 }] });
    assert.match(erros[0], /estoque insuficiente/);
  });

  test('total do pedido é calculado com duas casas', () => {
    assert.equal(calcularTotal([{ codigo: 'CP-1001', quantidade: 3 }, { codigo: 'CP-2040', quantidade: 2 }]), 318.7);
  });
});

describe('desconto por volume', () => {
  test('100 unidades recebem 5% de desconto', () => {
    assert.equal(calcularTotal([{ codigo: 'CP-2040', quantidade: 100 }]), 2327.5);
  });
});

describe('limite de itens', () => {
  test('pedido com 21 itens é rejeitado', () => {
    const itens = Array.from({ length: 21 }, () => ({ codigo: 'CP-2040', quantidade: 1 }));
    assert.ok(validarPedido({ cliente: 'X', itens }).includes('máximo de 30 itens por pedido'));
  });
});

describe('API HTTP', () => {
  test('GET /health responde 200 com status ok', async () => {
    const r = await fetch(`${base}/health`);
    assert.equal(r.status, 200);
    const corpo = await r.json();
    assert.equal(corpo.status, 'ok');
  });

  test('GET /api/pecas lista o catálogo', async () => {
    const r = await fetch(`${base}/api/pecas`);
    assert.equal(r.status, 200);
    assert.ok((await r.json()).length >= 3);
  });

  test('GET /api/pecas/:codigo inexistente responde 404', async () => {
    const r = await fetch(`${base}/api/pecas/CP-0000`);
    assert.equal(r.status, 404);
  });

  test('POST /api/pedidos cria pedido válido', async () => {
    const r = await fetch(`${base}/api/pedidos`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cliente: 'Montadora Y', itens: [{ codigo: 'CP-2040', quantidade: 10 }] })
    });
    assert.equal(r.status, 201);
    assert.equal((await r.json()).total, 245);
  });

  test('POST /api/pedidos com JSON inválido responde 400', async () => {
    const r = await fetch(`${base}/api/pedidos`, { method: 'POST', body: '{quebrado' });
    assert.equal(r.status, 400);
  });

  test('POST /api/pedidos inválido responde 422', async () => {
    const r = await fetch(`${base}/api/pedidos`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cliente: '', itens: [] })
    });
    assert.equal(r.status, 422);
  });

  test('GET /api/pedidos lista os pedidos criados', async () => {
    const r = await fetch(`${base}/api/pedidos`);
    assert.equal(r.status, 200);
    assert.ok(Array.isArray(await r.json()));
  });

  test('GET /api/pedidos/:id inexistente responde 404', async () => {
    const r = await fetch(`${base}/api/pedidos/99999`);
    assert.equal(r.status, 404);
  });
});
