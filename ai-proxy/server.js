/**
 * Localhost-only proxy + static server for EconomyGame MVP.
 *
 * Usage (from repo root):  npm start
 * Game:   http://127.0.0.1:8787/
 * Health: http://127.0.0.1:8787/health
 *
 * Env:    OLLAMA_URL (default http://127.0.0.1:11434)
 *         OLLAMA_MODEL (default gemma3:4b)
 *         PORT (default 8787)
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const HOST = '127.0.0.1';
const PORT = Number(process.env.PORT || 8787);
const OLLAMA_URL = (process.env.OLLAMA_URL || 'http://127.0.0.1:11434').replace(/\/$/, '');
const MODEL = process.env.OLLAMA_MODEL || 'gemma3:4b';
const OLLAMA_TIMEOUT_MS = Number(process.env.OLLAMA_TIMEOUT_MS || 55000);
const ROOT = path.resolve(__dirname, '..');
const DEFAULT_PAGE = 'EconomyGame_MVP (6).html';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
  '.md': 'text/plain; charset=utf-8',
};

function send(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, {
    ...CORS,
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(json),
  });
  res.end(json);
}

function sendText(res, status, text, contentType) {
  res.writeHead(status, { ...CORS, 'Content-Type': contentType });
  res.end(text);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

function buildPrompt(body) {
  if (typeof body.prompt === 'string' && body.prompt.trim()) return body.prompt.trim();

  const priceLine = body.price != null ? `Asking/reference price: ${body.price}.` : '';
  const terms = Array.isArray(body.preferredTerms) ? body.preferredTerms.join(', ') : '';
  const history = Array.isArray(body.messages)
    ? body.messages.map((m) => `${String(m.who || '').toUpperCase()}: ${m.text || ''}`).join('\n')
    : '';

  return `You are role-playing a counterparty in a business negotiation game.
Role: ${body.role || 'counterparty'}. Personality: ${body.personalityName || 'Negotiator'} (${body.personalityFlavor || ''}).
${priceLine}
You privately know (do not state outright unless it becomes relevant): ${body.hiddenInfo || ''}.
You respond to: ${terms}.
CLAIM HANDLING: The player cannot upload proof. Never ask for records or documentation. Accept off-game roleplay claims (career, experience, reputation) at face value if the player asserts them. Only challenge claims about in-game assets/portfolio if they conflict with known facts — push back in character, do not demand evidence.
Stay in character, be concise (1-3 sentences), never break the fourth wall, never reveal you are an AI.
Conversation so far:
${history}
PLAYER: ${body.playerMessage || ''}

Reply with ONLY a raw JSON object (no markdown fences, no extra text) matching exactly:
{"dialogue": "in-character reply, 1-3 sentences", "intent": "question|offer|accept|walk", "offer": {"totalPrice": number|null, "cashAtClosing": number|null, "closingSpeed": "fast|standard|extended", "termsOffered": [string], "priceAdjustment": number|null, "concessionSize": number|null}}`;
}

function stripFences(text) {
  return String(text || '')
    .replace(/```json\s*/gi, '')
    .replace(/```/g, '')
    .trim();
}

function parseNegotiationJson(text) {
  const clean = stripFences(text);
  try {
    return JSON.parse(clean);
  } catch {
    const start = clean.indexOf('{');
    const end = clean.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return JSON.parse(clean.slice(start, end + 1));
    }
    throw new Error('Model reply was not valid JSON');
  }
}

function normalizeResult(parsed) {
  if (!parsed || typeof parsed !== 'object') throw new Error('Empty model result');
  return {
    dialogue: typeof parsed.dialogue === 'string' ? parsed.dialogue : null,
    intent: parsed.intent || 'question',
    offer: parsed.offer && typeof parsed.offer === 'object' ? parsed.offer : null,
  };
}

async function ollamaChat(prompt, { repair = false } = {}) {
  const content = repair
    ? `Your previous reply was not valid JSON. Reply with ONLY a raw JSON object matching the schema — no markdown, no commentary.\n\n${prompt}`
    : prompt;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), OLLAMA_TIMEOUT_MS);
  try {
    const res = await fetch(`${OLLAMA_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        model: MODEL,
        stream: false,
        format: 'json',
        messages: [{ role: 'user', content }],
        options: { temperature: 0.4 },
      }),
    });
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      throw new Error(`Ollama ${res.status}: ${errText.slice(0, 200)}`);
    }
    const data = await res.json();
    return (data.message && data.message.content) || '';
  } finally {
    clearTimeout(timer);
  }
}

async function handleHealth(res) {
  try {
    const r = await fetch(`${OLLAMA_URL}/api/tags`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!r.ok) {
      return send(res, 503, { ok: false, error: `Ollama returned ${r.status}`, model: MODEL });
    }
    const data = await r.json();
    const names = (data.models || []).map((m) => m.name);
    const modelPresent = names.some((n) => n === MODEL || n.startsWith(`${MODEL}:`) || MODEL.startsWith(`${n}`));
    return send(res, 200, {
      ok: true,
      model: MODEL,
      modelPresent,
      models: names,
      gameUrl: `http://${HOST}:${PORT}/`,
    });
  } catch (e) {
    return send(res, 503, { ok: false, error: e.message || 'Ollama unreachable', model: MODEL });
  }
}

async function handleNegotiate(req, res) {
  let body;
  try {
    body = await readBody(req);
  } catch (e) {
    return send(res, 400, { error: e.message });
  }

  if (!body.playerMessage && !body.prompt) {
    return send(res, 400, { error: 'Missing playerMessage or prompt' });
  }

  const prompt = buildPrompt(body);
  try {
    let text = await ollamaChat(prompt);
    try {
      return send(res, 200, normalizeResult(parseNegotiationJson(text)));
    } catch {
      text = await ollamaChat(prompt, { repair: true });
      return send(res, 200, normalizeResult(parseNegotiationJson(text)));
    }
  } catch (e) {
    const msg = e.name === 'AbortError' ? 'Ollama timeout' : e.message || 'Ollama failed';
    return send(res, 502, { error: msg });
  }
}

function safePath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const rel = decoded === '/' ? `/${DEFAULT_PAGE}` : decoded;
  const normalized = path.normalize(path.join(ROOT, rel));
  if (!normalized.startsWith(ROOT)) return null;
  return normalized;
}

function serveStatic(req, res, url) {
  const filePath = safePath(url.pathname);
  if (!filePath) {
    return sendText(res, 403, 'Forbidden', 'text/plain; charset=utf-8');
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      return sendText(res, 404, 'Not found', 'text/plain; charset=utf-8');
    }
    const ext = path.extname(filePath).toLowerCase();
    const type = MIME[ext] || 'application/octet-stream';
    fs.readFile(filePath, (readErr, data) => {
      if (readErr) {
        return sendText(res, 500, 'Read error', 'text/plain; charset=utf-8');
      }
      res.writeHead(200, { ...CORS, 'Content-Type': type });
      res.end(data);
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${HOST}:${PORT}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS);
    return res.end();
  }

  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      return await handleHealth(res);
    }
    if (req.method === 'POST' && url.pathname === '/negotiate') {
      return await handleNegotiate(req, res);
    }
    if (req.method === 'GET') {
      return serveStatic(req, res, url);
    }
    return send(res, 404, { error: 'Not found' });
  } catch (e) {
    return send(res, 500, { error: e.message || 'Server error' });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`EconomyGame server: http://${HOST}:${PORT}/`);
  console.log(`  MVP:    http://${HOST}:${PORT}/${encodeURI(DEFAULT_PAGE)}`);
  console.log(`  Ollama: ${OLLAMA_URL}  model: ${MODEL}`);
  console.log(`  GET  /health`);
  console.log(`  POST /negotiate`);
});
