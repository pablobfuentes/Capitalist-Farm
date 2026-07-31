# EconGame — Godot 4 Project

Godot port of **EconomyGame MVP 6** (Capital Farm supply-chain sim).

## Requirements

- **Godot 4.3+** (4.4 stable recommended)
- **Node.js 18+** (to export farm content JSON from the JS source)

## Quick start

1. Install [Godot 4](https://godotengine.org/download) and open this folder as the project:
   ```
   EconGame/godot/
   ```
2. Export farm content from the MVP JS (run after changing `js/farm-supply-chain.js`):
   ```bash
   npm run export:farm-content
   ```
3. Press **F5** — runs the main menu (`ui/screens/main_menu.tscn`).
4. **Run unit tests (recommended)** — bypasses GUT bottom-panel config entirely:
   - Open `scenes/run_gut_tests.tscn`
   - Press **F6** (Run Current Scene)
   - Tests load settings from `res://.gutconfig.json` (`res://tests`, prefix `test_`)
   - Or from repo root: `npm run test:gut` (headless; requires Godot on PATH or `GODOT_BIN`)

   **Avoid the GUT bottom panel “Run All”** if you see `Nil` → `bool` errors — that path uses separate editor user settings that can corrupt. The scene above does not.

   Optional: **Project → Tools → GUT** still works for browsing individual test scripts once settings are loaded via **Settings → Load → `res://.gutconfig.json`** (use the full file in repo root `godot/.gutconfig.json`).

## Project layout

| Path | Purpose |
|------|---------|
| `autoload/` | Game, EventBus, Content, AiClient singletons |
| `core/state/` | RunState, Portfolio, BusinessInstance |
| `core/systems/` | SynergySystem, FinanceSystem, TurnResolver |
| `core/util/` | MathUtil, SeededRng |
| `data/` | `farm_content.json` + Resource class scripts |
| `scenes/` | Runnable scenes (smoke test, future UI) |
| `tests/` | GUT tests + JSON fixtures from MVP |
| `ui/` | UI scenes (Phase 3+) |

## Architecture rules

- **`core/`** must not reference UI nodes or HTTP.
- **Content** loads from `data/farm_content.json`, generated from `js/farm-supply-chain.js`.
- **HTML MVP** stays the parity oracle until Phase 6 checklist in `8.0_godot_migration.md`.

## Headless (optional)

If Godot is on your PATH:

```bash
godot --headless --path godot --quit-after 1
```

## AI negotiation

The optional local proxy is unchanged (`npm start` at repo root). `AiClient` autoload checks `http://127.0.0.1:8787/health` at startup.

## Migration status

See [`../8.0_godot_migration.md`](../8.0_godot_migration.md) for phase checklist.

**Play:** F5 → New Capital Farm Run → buy businesses → **Improve** → Advance Turn. Supply chain links appear in the third column when you own connected assets.
**Smoke test:** Main menu → Run Smoke Test (or set main scene to `scenes/smoke_test.tscn`).
