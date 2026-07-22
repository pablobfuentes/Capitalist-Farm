# Local AI Negotiation — Design

## Understanding summary

- Connect negotiation chat in the single-file HTML game to local Ollama (`gemma3:4b`) via a tiny localhost proxy so NPC replies work when the game is opened via `file://`.
- Purpose: leave Claude-hosted setup; enable reliable local testing of AI negotiations.
- Audience: local development / playtesting (you).
- Constraints: `file://` open; Ollama + Gemma already on PC; economic accept/reject stays in the local utility engine; AI handles dialogue + structured offer parsing.
- Near-term deliverable: HTML → proxy → Ollama, with graceful “AI offline” fallback (canned/regex).
- Later goal: packaged desktop app that integrates/expects a local model (out of scope for first implementation).
- Non-goals for this step: cloud APIs, Electron/Tauri packaging, changing core economy math.

## Assumptions

- Ollama reachable at `http://127.0.0.1:11434`.
- Default model tag `gemma3:4b` (override with `OLLAMA_MODEL` if `ollama list` differs).
- Simplest proxy stack on the machine (Node or Python — chosen at implementation).
- Existing prompt/JSON contract preserved; only transport changes (Anthropic → proxy → Ollama).
- Proxy binds localhost only (not LAN-exposed).

## Decision log

| Decision | Alternatives considered | Why chosen |
|----------|-------------------------|------------|
| Ollama + Gemma as local LLM | LM Studio, llama.cpp, cloud APIs | Already installed and running |
| Localhost proxy between HTML and Ollama | Browser → Ollama direct; jump to Electron/Tauri | Reliable with `file://`; clean contract for future desktop app |
| Keep regex/canned fallback + “AI offline” note | Block chat; silent fallback | Game stays playable; player knows AI is offline |
| Simplest available proxy language | Fixed Node or Python preference | Lowest friction at implementation time |
| Approach 1 (HTML + proxy now) | Direct Ollama; desktop-first | Proves chat path before packaging |
| Deal outcomes stay in utility engine | Let LLM accept/reject money deals | Existing design; AI is dialogue/parsing only |
| Proxy port `8787`, Ollama `11434`, model `gemma3:4b` | Other ports/models | Matches local install; env-overridable |

## Final design

### Architecture

```
HTML (file://) → http://127.0.0.1:8787/negotiate → Ollama (:11434) → gemma3:4b
                 GET /health (optional early check)
```

1. **Game** — negotiation UI + utility engine unchanged. Replace Anthropic call in `callNegotiationAI` with proxy POST. On failure: existing fallback + “AI offline” note.
2. **Proxy** — localhost-only HTTP server; builds prompt, calls Ollama, returns parsed JSON.
3. **Ollama** — existing install; model `gemma3:4b`.

### Components & API

**Game**

- `POST http://127.0.0.1:8787/negotiate` with counterparty context, history, player message.
- Optional `GET /health` when opening a negotiation.
- On error: `fallbackExtractOffer` + system chat note “AI offline — using basic replies.”

**Proxy** (`ai-proxy/`)

- Listen: `127.0.0.1:8787` only.
- `POST /negotiate` → Ollama chat → `{ dialogue, intent, offer }`.
- `GET /health` → `{ ok: true, model: "gemma3:4b" }` if Ollama responds.
- Strip markdown fences; retry once on bad JSON; then `502`.

**Contract (stable for desktop later)**

- Success: `200` + `{ dialogue, intent, offer }` matching existing game schema.
- Failure: `4xx/5xx` + `{ error: "..." }` → game offline fallback.

**Run order**

1. Start Ollama  
2. Start proxy  
3. Open the HTML file  

### Errors, edge cases, testing

**Errors:** proxy/Ollama down → fallback + offline note; bad JSON → one repair retry then fallback; timeout ~45–60s then fallback.

**Edge cases:** one negotiation modal at a time; walk-away needs no AI; CORS solved by proxy; localhost-only bind.

**Risks:** Gemma JSON reliability weaker than Claude — parsing + fallback required; both Ollama and proxy must be running for AI replies.

**Test plan**

1. `/health` with Ollama up → ok  
2. Negotiation with both running → in-character JSON replies  
3. Stop proxy → fallback + offline note  
4. Stop Ollama only → same  
5. Accept/reject/counter still driven by utility engine  

## Out of scope (later)

- Electron/Tauri (or similar) desktop packaging using the same `/negotiate` contract
- In-game settings UI for model/URL
- Bundling a model binary inside the app
