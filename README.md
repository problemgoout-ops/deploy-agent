# deploy-agent — OpenClaw Skill

AI-agent deployment skill for OpenClaw. Full-cycle deployment: SSH → Node.js → OpenClaw → Ollama → Telegram bot with memory and embeddings.

## Files
- `SKILL.md` — full deployment instructions and safety rules
- `TESTS.md` — test documentation (18 test cases, 5 suites)
- `tests.sh` — executable test script (18/18 passing)

## Key Safety Features (from Elena case post-mortem, 2026-06-04)
- **Save-Game instantly** — write credentials to file immediately, never defer
- **Token verification** — validate length (46 chars) and Telegram API before restart
- **Checkpoints** — 10 checkpoints for recovery after session crash
- **Human-readable errors** — never send raw error messages to users
- **Timeouts** — SSH (10s), curl (15s), systemctl (5s)
- **Dry-run config** — validate JSON before `systemctl restart`

## Test Results
18/18 tests passing across 5 suites:
- Data persistence (4 tests)
- Token verification (4 tests)
- User communication (5 tests)
- Timeouts (2 tests)
- Config dry-run (2 tests)

