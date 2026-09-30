'use strict';

// API do portal de pedidos B2B da Carparts.
// Sem dependências externas: usa apenas o módulo http do Node.js.

const http = require('node:http');

const VERSION = process.env.APP_VERSION || 'dev';
const COMMIT = process.env.GIT_COMMIT || 'local';
const AMBIENTE = process.env.AMBIENTE || 'local';

const pecas = [
  { codigo: 'CP-1001', descricao: 'Pastilha de freio dianteira', estoque: 420, preco: 89.9 },
  { codigo: 'CP-2040', descricao: 'Filtro de óleo', estoque: 1300, preco: 24.5 },
  { codigo: 'CP-3310', descricao: 'Amortecedor traseiro', estoque: 85, preco: 312.0 }
];

const pedidos = [];

function enviarJson(res, status, corpo) {
  const dados = JSON.stringify(corpo);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(dados)
  });
  res.end(dados);
}

function lerCorpo(req) {
  return new Promise((resolve, reject) => {
    let bruto = '';
    req.on('data', (parte) => {
      bruto += parte;
      if (bruto.length > 1e5) {
        reject(new Error('corpo muito grande'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(bruto ? JSON.parse(bruto) : {});
      } catch (erro) {
        reject(erro);
      }
    });
  });
}

function validarPedido(pedido) {
  const erros = [];
  if (!pedido || typeof pedido !== 'object') {
    return ['pedido inválido'];
  }
  if (!pedido.cliente || typeof pedido.cliente !== 'string') {
    erros.push('cliente é obrigatório');
  }
  if (!Array.isArray(pedido.itens) || pedido.itens.length === 0) {
    erros.push('itens é obrigatório');
  } else {
    pedido.itens.forEach((item, i) => {
      const peca = pecas.find((p) => p.codigo === item.codigo);
      if (!peca) {
        erros.push(`item ${i + 1}: peça ${item.codigo} não existe`);
      } else if (!Number.isInteger(item.quantidade) || item.quantidade <= 0) {
        erros.push(`item ${i + 1}: quantidade inválida`);
      } else if (item.quantidade > peca.estoque) {
        erros.push(`item ${i + 1}: estoque insuficiente`);
      }
    });
  }
  return erros;
}

function calcularTotal(itens) {
  const total = itens.reduce((soma, item) => {
    const peca = pecas.find((p) => p.codigo === item.codigo);
    return soma + peca.preco * item.quantidade;
  }, 0);
  return Math.round(total * 100) / 100;
}

async function rotear(req, res) {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && url.pathname === '/health') {
    return enviarJson(res, 200, { status: 'ok', versao: VERSION, commit: COMMIT, ambiente: AMBIENTE });
  }

  if (req.method === 'GET' && url.pathname === '/api/pecas') {
    return enviarJson(res, 200, pecas);
  }

  const matchPeca = url.pathname.match(/^\/api\/pecas\/([A-Z0-9-]+)$/);
  if (req.method === 'GET' && matchPeca) {
    const peca = pecas.find((p) => p.codigo === matchPeca[1]);
    return peca ? enviarJson(res, 200, peca) : enviarJson(res, 404, { erro: 'peça não encontrada' });
  }

  if (req.method === 'POST' && url.pathname === '/api/pedidos') {
    let pedido;
    try {
      pedido = await lerCorpo(req);
    } catch {
      return enviarJson(res, 400, { erro: 'JSON inválido' });
    }
    const erros = validarPedido(pedido);
    if (erros.length > 0) {
      return enviarJson(res, 422, { erros });
    }
    const novo = {
      id: pedidos.length + 1,
      cliente: pedido.cliente,
      itens: pedido.itens,
      total: calcularTotal(pedido.itens),
      criadoEm: new Date().toISOString()
    };
    pedidos.push(novo);
    return enviarJson(res, 201, novo);
  }

  if (req.method === 'GET' && url.pathname === '/api/pedidos') {
    return enviarJson(res, 200, pedidos);
  }

  const matchPedido = url.pathname.match(/^\/api\/pedidos\/(\d+)$/);
  if (req.method === 'GET' && matchPedido) {
    const pedido = pedidos.find((p) => p.id === Number(matchPedido[1]));
    return pedido ? enviarJson(res, 200, pedido) : enviarJson(res, 404, { erro: 'pedido não encontrado' });
  }

  return enviarJson(res, 404, { erro: 'rota não encontrada' });
}

function criarServidor() {
  return http.createServer((req, res) => {
    rotear(req, res).catch(() => enviarJson(res, 500, { erro: 'erro interno' }));
  });
}

module.exports = { criarServidor, validarPedido, calcularTotal };
