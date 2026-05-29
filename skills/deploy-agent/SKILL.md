---
name: deploy-agent
description: "Развёртывание OpenClaw-агента на чистом сервере 'под ключ': SSH, Node.js, OpenClaw, Ollama, эмбеддинги, память, Telegram-бот, fallback-модели, базовые скиллы (Agent Doctor, Agent Forge, ru-text). Triggers: 'разверни агента', 'deploy agent', 'подними бота', 'новый краб', 'краб', 'настрой сервер', 'установи OpenClaw', 'создай бота на сервере', 'разверни на сервере'."
---

# Deploy Agent 🦀

Полный скилл: от SSH-подключения к пустой машине до работающего Telegram-бота с памятью и эмбеддингами.

**Что делает:** проводит полный цикл развёртывания OpenClaw-агента на удалённом Linux-сервере.

**После разворота — обязательно:**
1. Записать сервер в MEMORY.md (секция владельца) + SECRETS.md (пароли)
2. Выполнить полную диагностику через server-connect скилл
3. Записать дату проверки в MEMORY.md

---

## Порядок работы

### Шаг 0: Собрать информацию

**Если тебе написал новый человек и просит развернуть агента — запроси у него:**

1. **SSH-доступ к серверу:** `user@host` (или IP), пароль или путь к ключу
2. **API ключ для LLM:** если Ollama Cloud — нужен ключ с https://ollama.com, если OpenAI/Anthropic — их ключ
   - Для Ollama Cloud: `ollama login` на сервере или готовый OLLAMA_API_KEY
3. **Telegram-бота:** токен от @BotFather ИЛИ скажи «создам сам»:
   - Открыть @BotFather → `/newbot` → выбрать имя → скопировать токен
   - Прислать токен мне

**Шаблон первого ответа новому пользователю:**

```
Привет! Чтобы развернуть тебе агента, мне понадобится:

1. SSH-доступ к серверу — хост (IP), пользователь, пароль
2. API-ключ для LLM-моделей:
   — Если Ollama Cloud: ключ с https://ollama.com (или я помогу настроить)
   — Если OpenAI/Anthropic: твой API-ключ
3. Telegram-бот:
   — Токен от @BotFather (создай через /newbot если нет)
   — Твой Telegram ID

Жду данные — как пришлёшь, начну разворот.
```

**Если человек что-то не понимает** — не жди, напиши что именно ты от него ждёшь и зачем это нужно. Например:
- «SSH-доступ нужен чтобы я мог подключиться к серверу и всё настроить»
- «API-ключ Ollama Cloud нужен чтобы использовать облачные модели (deepseek, kimi, glm)»
- «Токен бота нужен чтобы подключить твоего агента к Telegram»

**⚠️ Если человек НЕ в MEMORY.md** — сначала спроси Алексея: «Мне написал {имя} ({id}), можно с ним работать?» Только после разрешения начинай развёртывание.

**⚠️ Если человек уже в MEMORY.md** — сразу запрашивай данные и начинай работу.

Все credentials записывай в SECRETS.md DevOps-агента, НЕ в память агента и НЕ в git.

### 🆕 Шаг 00: Валидация API ключа ДО развёртывания

**КРИТИЧНО: проверять API ключ сразу после получения, до любых других действий.**

Это предотвращает ситуацию «всё развернули, а ключ не работает».

```bash
# Для Ollama Cloud — проверить ключ на СВОЁМ сервере (на титов-main):
# Это работает даже если целевой сервер ещё не готов
curl -s --max-time 15 http://127.0.0.1:11434/api/chat \
  -H "Authorization: Bearer {API_KEY}" \
  -d '{"model":"deepseek-v4-pro:cloud","messages":[{"role":"user","content":"Say hi"}],"stream":false,"max_tokens":5}'

# Если ответ — 401 unauthorized → ключ НЕВЕРНЫЙ, просить новый
# Если ответ содержит "message" → ключ рабочий ✅, можно продолжать
```

**Для OpenAI ключа:**
```bash
curl -s --max-time 10 https://api.openai.com/v1/models \
  -H "Authorization: Bearer {API_KEY}"
```

**Для Anthropic ключа:**
```bash
curl -s --max-time 10 https://api.anthropic.com/v1/messages \
  -H "x-api-key: {API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
```

**Если проверка провалилась:**
1. Сказать пользователю: «Ключ невалидный, проверь его в личном кабинете»
2. Для Ollama: дать ссылку https://ollama.com/settings/keys
3. Для OpenAI: https://platform.openai.com/api-keys
4. Для Anthropic: https://console.anthropic.com/settings/keys
5. **НЕ продолжать развёртывание** пока ключ не пройдёт проверку

**Если проверка прошла ✅:**
- Продолжать развёртывание
- Записать последние 10 символов ключа в логи (для сверки потом)

---

## Часть 1: SSH и базовая настройка

### Шаг 1: SSH-подключение

```bash
ssh user@host
# или по IP
ssh user@192.168.x.x
# или с ключом
ssh -i ~/.ssh/my_key user@host
```

Если ключ не настроен — создай и скопируй:

```bash
# Локально
ssh-keygen -t ed25519 -C "openclaw-setup"
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host
```

### Шаг 2: Базовая настройка системы

```bash
# Обновление
sudo apt update && sudo apt upgrade -y

# Необходимые пакеты
sudo apt install -y git curl build-essential

# Таймзона (важно для кронов и напоминаний)
sudo timedatectl set-timezone Europe/Moscow  # заменить на нужную

# Проверить
date
```

---

## Часть 2: Установка OpenClaw

### Шаг 3: Установка Node.js

```bash
# Node 24 (рекомендуется)
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs

# Проверить
node --version   # v24.x.x
npm --version
```

Для macOS:
```bash
brew install node@24
```

### Шаг 4: Установка OpenClaw

**Вариант A — скрипт установки:**
```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

**Вариант B — через npm:**
```bash
npm i -g openclaw@latest
```

### Шаг 5: Онбординг

```bash
openclaw onboard --install-daemon
```

Мастер проведёт через:
- Выбор провайдера моделей (Anthropic, OpenAI, Ollama и т.д.)
- Ввод API-ключа
- Настройку gateway

### Шаг 6: Проверка

```bash
openclaw gateway status
# Должен показать: running, port 18789
```

---

## Часть 3: Ollama + локальные модели + эмбеддинги

### Шаг 7: Установка Ollama

```bash
# Linux
curl -fsSL https://ollama.com/install.sh | sh

# macOS
brew install ollama
```

Запуск как сервис (Linux):
```bash
sudo systemctl enable ollama
sudo systemctl start ollama
```

Запуск на macOS — Ollama запускается как приложение, или:
```bash
ollama serve
```

### Шаг 8: Скачивание моделей

**Для чата (выбрать одну):**

| Модель | RAM | Размер | Когда |
|--------|-----|--------|-------|
| `qwen2.5:7b` | 8 GB | 4.7 GB | Лёгкая, быстрая |
| `qwen2.5:14b` | 16+ GB | 9 GB | Мощнее |
| `llama3.3:8b` | 8 GB | 4.9 GB | Универсальная |

```bash
# Лёгкая и быстрая (4.7 GB) — для машин с 8 GB RAM
ollama pull qwen2.5:7b

# Мощнее (9 GB) — для машин с 16+ GB RAM
ollama pull qwen2.5:14b

# Быстрая универсальная (4.9 GB)
ollama pull llama3.3:8b
```

**Для эмбеддингов (обязательно):**
```bash
ollama pull nomic-embed-text
```

Проверить:
```bash
ollama list
```

### Шаг 9: Настройка провайдера Ollama в OpenClaw

Добавить в `~/.openclaw/openclaw.json` → `models.providers`:

```json
"ollama": {
  "baseUrl": "http://127.0.0.1:11434",
  "api": "ollama",
  "apiKey": "{OLLAMA_API_KEY}",
  "models": [
    {
      "id": "qwen2.5:14b",
      "name": "Qwen 2.5 14B (Local)",
      "api": "ollama",
      "input": ["text"],
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
      "contextWindow": 131072,
      "maxTokens": 8192
    }
  ]
}
```

**⚠️ ВАЖНО: `apiKey` в провайдере Ollama обязателен для cloud-моделей!**
Без него OpenClaw не сможет передавать ключ в API-запросы к Ollama, и cloud-модели будут возвращать 401.

**Замени `qwen2.5:14b` на ту модель, которую скачал.**

**Для cloud-only стратегии** (только облачные модели, без локальных):
```json
"ollama": {
  "api": "ollama",
  "baseUrl": "http://127.0.0.1:11434",
  "apiKey": "{OLLAMA_API_KEY}"
}
```

Добавить алиас в `agents.defaults.models`:
```json
"ollama/qwen2.5:14b": {
  "alias": "QWEN-LOCAL"
}
```

---

## Часть 4: Память и эмбеддинги

### Шаг 10: Настройка memorySearch

Добавить в `~/.openclaw/openclaw.json` → `agents.defaults`:

```json
"memorySearch": {
  "provider": "ollama",
  "remote": {
    "baseUrl": "http://localhost:11434"
  },
  "model": "nomic-embed-text",
  "queryInputType": "query",
  "documentInputType": "passage"
}
```

Это включает:
- **Семантический поиск** по памяти (memory_search)
- **Индексацию** всех файлов memory/*.md
- **Бесплатно** — всё работает локально через Ollama

### Шаг 11: Создание структуры памяти

```bash
# Директория для ежедневных дампов
mkdir -p ~/.openclaw/workspace/memory

# Файл основной памяти
cat > ~/.openclaw/workspace/MEMORY.md << 'EOF'
# MEMORY.md — {DISPLAY_NAME}
EOF
```

### Шаг 12: Настройка политики памяти

Создать `~/.openclaw/workspace/MEMORY-POLICY.md` (см. `references/memory-policy.md`).

### Шаг 13: QMD (опционально, для продвинутой памяти)

Добавить в `~/.openclaw/openclaw.json` → `memory`:

```json
"memory": {
  "backend": "qmd",
  "citations": "auto",
  "qmd": {
    "includeDefaultMemory": true,
    "sessions": {
      "enabled": true,
      "retentionDays": 90
    },
    "update": {
      "interval": "5m",
      "debounceMs": 15000
    },
    "limits": {
      "maxResults": 6,
      "timeoutMs": 4000
    }
  }
}
```

---

## Часть 5: Создание агента (бота)

### Шаг 14: Получить Telegram-токен

1. Открыть @BotFather в Telegram
2. Отправить `/newbot`
3. Выбрать имя и username
4. Скопировать токен (формат: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

### Шаг 15: Создать workspace агента

```bash
mkdir -p ~/.openclaw/workspace-{agent_id}
```

Создать файлы в `~/.openclaw/workspace-{agent_id}/`:

**SOUL.md** — личность:
```markdown
# SOUL.md — {DISPLAY_NAME}

## Кто я
{2-3 предложения: кто бот, его роль, экспертиза}

## Стиль
- {тон и характер, 4-6 пунктов}

## Язык
Русский по умолчанию. Technical terms stay in English.

## Приоритеты
1. {приоритет 1}
2. {приоритет 2}

## Границы
- {граница 1}
- {граница 2}
```

**AGENTS.md** — роли и правила:
```markdown
# AGENTS.md — {DISPLAY_NAME}

## Роль
{Одно предложение — роль бота}

## Session Startup
1. Read SOUL.md — это кто ты
2. Read USER.md — это кто тебе пишет
3. Check HEARTBEAT.md if exists

## Политика памяти
См. MEMORY-POLICY.md

## Зона ответственности
- {ответственность 1}
- {ответственность 2}

## Что НЕ делать
- {ограничение 1}
- {ограничение 2}

## Алерты
- 🔴 CRITICAL → сразу писать владельцу
- 🟡 WARNING → логировать + писать если повторяется
- 🟢 INFO → только в лог
```

**IDENTITY.md** — карточка:
```markdown
# IDENTITY.md

- **Name:** {DISPLAY_NAME}
- **Creature:** {роль}
- **Vibe:** {характер в 3-5 словах}
- **Emoji:** {эмодзи}
```

**USER.md** — кто пишет:
```markdown
# USER.md

- **Name:** {имя владельца}
- **Telegram:** {username}
- **Timezone:** {таймзона}
- **Role:** Owner
```

**MEMORY.md** — стартовый файл:
```markdown
# MEMORY.md — {DISPLAY_NAME}
```

### Шаг 16: Настроить openclaw.json

Добавить в `agents.list`:
```json
{
  "id": "{agent_id}",
  "name": "{DISPLAY_NAME}",
  "workspace": "~/.openclaw/workspace-{agent_id}",
  "model": "ollama/qwen2.5:14b"
}
```

Для cloud-модели с fallback на локальную:
```json
"model": {
  "primary": "anthropic/claude-sonnet-4-6",
  "fallbacks": ["ollama/qwen2.5:14b"]
}
```

Добавить в `channels.telegram.accounts`:
```json
"{agent_id}": {
  "name": "{DISPLAY_NAME}",
  "dmPolicy": "allowlist",
  "botToken": "{ТОКЕН_ОТ_BOTFATHER}",
  "allowFrom": [{TELEGRAM_USER_ID}],
  "groupPolicy": "allowlist",
  "streaming": {
    "mode": "partial"
  }
}
```

Добавить в `bindings`:
```json
{
  "type": "route",
  "agentId": "{agent_id}",
  "match": {
    "channel": "telegram",
    "accountId": "{agent_id}"
  }
}
```

⚠️ **КРИТИЧНО:** Все три секции (`agents.list`, `channels.telegram.accounts`, `bindings`) обязательны! Без binding сообщения уйдут в main-бота.

### Шаг 17: Перезапустить gateway

```bash
openclaw gateway restart
```

### Шаг 18: Проверить

```bash
# Проверить что агент виден
openclaw agents list

# Проверить что сессия создалась правильно:
ls ~/.openclaw/agents/{agent_id}/sessions/
# Должно быть: agent:{agent_id}:telegram:direct:{user_id}
# Если agent:main:... — не работает binding, проверить конфиг
```

Отправить сообщение боту в Telegram и убедиться что отвечает.

---

## Часть 6: Модели (cloud-only стратегия)

По умолчанию — **cloud-only**: только облачные модели для чата, локальные модели только для эмбеддингов (nomic-embed-text).

**Преимущества cloud-only:**
- Экономия RAM (4-9 GB) и диска (5-10 GB)
- Всегда актуальные модели
- Проще обновлять
- Сервер не тормозит от локальных моделей

**Настройка fallback между cloud-моделями:**
```json
"model": {
  "primary": "ollama/deepseek-v4-pro:cloud",
  "fallbacks": ["ollama/glm-5.1:cloud", "ollama/kimi-k2.6:cloud"]
}
```

**Если владелец явно хочет локальную fallback-модель** (требует RAM и диск):
```json
"model": {
  "primary": "ollama/deepseek-v4-pro:cloud",
  "fallbacks": ["ollama/qwen2.5:7b"]
}
```
Смотри Часть 8 для проверки ресурсов ПЕРЕД установкой локальных моделей.

---

## Чеклист установки

- [ ] SSH доступ работает
- [ ] Система обновлена, таймзона правильная
- [ ] Node.js установлен (v24+)
- [ ] OpenClaw установлен и gateway запущен
- [ ] Ollama установлена и работает
- [ ] Модель для чата скачана (`ollama list`)
- [ ] `nomic-embed-text` скачан для эмбеддингов
- [ ] `memorySearch` настроен в `openclaw.json`
- [ ] Структура памяти создана (`memory/`, `MEMORY.md`, `MEMORY-POLICY.md`)
- [ ] Telegram-токен получен от @BotFather
- [ ] Workspace агента создан (SOUL, AGENTS, IDENTITY, USER, MEMORY)
- [ ] Агент добавлен в `agents.list`
- [ ] Telegram account добавлен в `channels.telegram.accounts`
- [ ] Binding добавлен
- [ ] Gateway перезапущен
- [ ] Сообщения идут в правильного агента
- [ ] Agent Doctor скилл установлен
- [ ] Agent Forge скилл установлен
- [ ] ru-text скилл установлен (опционально)
- [ ] Симлинки скиллов в workspace агента

---

## Частые ошибки

1. **Нет binding** — сообщения идут в main. Всегда добавляйте binding.
2. **Нет streaming config** — добавьте `"streaming": {"mode": "partial"}` в account.
3. **dmPolicy "pairing"** — используйте `"allowlist"` с explicit `allowFrom`.
4. **Ollama не запущена** — проверьте `ollama list`, при ошибке — `ollama serve`.
5. **Эмбеддинги не работают** — проверьте что `nomic-embed-text` скачан: `ollama list | grep nomic`.
6. **Hardcoded paths** — используйте `~/.openclaw/` вместо абсолютных путей.
7. **Gateway перезаписал конфиг** — всегда проверяйте конфиг после рестарта.

---

## Часть 7: Защита credentials на Linux

Keychain доступен только на macOS. На Linux используй один из вариантов:

### Вариант A: `pass` (рекомендуется)

```bash
# Установка
sudo apt install pass

# Инициализация (нужен GPG-ключ)
gpg --full-generate-key  # RSA, 4096 bit
pass init <gpg-key-id>

# Сохранение
pass insert ssh/fornex-3-root
pass insert telegram/bot-token

# Чтение
pass show ssh/fornex-3-root

# Автодополнение
pass git init  # опционально, для истории
```

### Вариант B: `openssl enc` (проще, без GPG)

```bash
# Создание хранилища
mkdir -p ~/.openclaw/.creds
chmod 700 ~/.openclaw/.creds

# Шифрование
echo "PASSWORD" | openssl enc -aes-256-cbc -salt -pbkdf2 -out ~/.openclaw/.creds/fornex-3.enc

# Чтение (потребует пароль)
openssl enc -d -aes-256-cbc -pbkdf2 -in ~/.openclaw/.creds/fornex-3.enc
```

### Вариант C: TOOLS.md с правами 600 (минимум)

```bash
chmod 600 ~/.openclaw/agents/*/agent/TOOLS.md
```

⚠️ **Правило:** credentials хранить ТОЛЬКО в SECRETS.md DevOps-агента. Никогда не писать пароли в MEMORY.md, AGENTS.md, скрипты или git.

Для агента на чужом сервере: пароли хранятся централизованно в SECRETS.md DevOps-агента (на титов-main). Агент на сервере пользователя НЕ хранит пароли — DevOps-агент подключается к нему удалённо.

---

## Часть 8: Проверка ресурсов ПЕРЕД установкой

Перед установкой Ollama и моделей — проверь ресурсы:

```bash
# RAM
free -h
# Диск
df -h /
# CPU
nproc
```

### Ограничения

| Свободно RAM | Что ставить |
|---------------|-------------|
| < 2 GB | Только nomic-embed-text (274 MB RAM). Чат — только cloud. |
| 2-4 GB | nomic-embed-text. Чат — только cloud. |
| 4-8 GB | nomic-embed-text + qwen2.5:7b (если нужен fallback) |
| 8+ GB | nomic-embed-text + qwen2.5:14b (если нужен fallback) |

| Свободно диска | Что ставить |
|----------------|-------------|
| < 5 GB | Только nomic-embed-text (274 MB). Предупредить владельца. |
| 5-15 GB | nomic-embed-text. Чат-модель — только если хватает. |
| 15+ GB | Полная установка с моделью. |

**Если ресурсов мало — предупредить владельца перед установкой.**

**Стратегия cloud-only (без локальных моделей чата):**
- Установить ТОЛЬКО `nomic-embed-text` для memorySearch
- Чат-модели не ставить — использовать только cloud
- Это экономит 5-10 GB диска и 4-9 GB RAM
- Требует стабильного интернета на сервере

---

## Часть 9: Порядок работы с данными

**При старте сессии или после компактификации:**

1. Проверить MEMORY.md — серверы по владельцам
2. SECRETS.md — credentials (grep по имени, НЕ читать целиком)
3. memory_search — восстановить контекст
4. AGENTS.md — роль и правила

**Credentials хранятся ТОЛЬКО в:**
- SECRETS.md DevOps-агента (основное место)
- НЕ в TOOLS.md, НЕ в памяти агента, НЕ в git

**Порядок чтения при старте (для агента на чужом сервере):**
1. SOUL.md — кто я
2. USER.md — кто пишет
3. AGENTS.md — роль и правила
4. MEMORY.md — долгосрочная память
5. memory_search — восстановить контекст

---

## Часть 10: Базовые скиллы (Agent Doctor + Agent Forge)

Два скилла, которые должны быть у каждого нового агента с первого дня. Это не опция — это минимум для продуктивной работы.

**Философия:** если бы вы начинали сегодня с нуля — вы бы начали с этого. Не нужно проходить путь из месяцев проб и ошибок. Берёте готовое и сразу работающее.

### Шаг 19: Установить Agent Doctor

**Что делает:** комплексная самодиагностика OpenClaw. Проверяет память, кроны, конфиг, файлы, gateway, систему, безопасность. Находит проблемы и предлагает конкретные решения.

**Триггеры:** «продиагностируй себя», «самодиагностика», «проверь систему», «health check»

```bash
# Клонировать репозиторий
mkdir -p ~/.openclaw/skills/agent-doctor
cd /tmp && git clone https://github.com/AlekseiUL/openclaw-superagent.git
cp /tmp/openclaw-superagent/skills/agent-doctor/SKILL.md ~/.openclaw/skills/agent-doctor/SKILL.md
```

**Что проверяет Agent Doctor (7 категорий):**

| Категория | Что проверяет |
|-----------|-------------|
| 🧠 Память | SQLite, WAL mode, записи, memorySearch, embedding провайдер |
| ⏰ Кроны | Список, статус, ошибки, падения |
| ⚙️ Конфиг | JSON валидность, модель, каналы, плагины |
| 📁 Файлы | SOUL.md, IDENTITY.md, AGENTS.md, HEARTBEAT.md, скиллы |
| 🔧 Gateway | Статус, аптайм, ошибки в логах, порт |
| 💾 Система | ОС, Node.js, Python, диск, версия OpenClaw |
| 🛡️ Безопасность | Gateway bind, auth mode, API ключи в открытых файлах |

**Автофиксы (после подтверждения):**
- WAL mode → `PRAGMA journal_mode=WAL;`
- memorySearch отключен → включить в конфиге
- Gateway на 0.0.0.0 → перевести на 127.0.0.1
- Старый Node.js → обновить
- Диск заполнен → очистить логи/кеш

### Шаг 20: Установить Agent Forge

**Что делает:** создание и улучшение скиллов и агентов OpenClaw. Три режима: создание скилла (11 шагов), создание агента (9 шагов), улучшение существующего (5 шагов).

**Триггеры:** «создай скилл», «новый скилл», «создай агента», «новый агент», «улучши скилл», «скиллмейкер»

```bash
# Из того же репозитория
mkdir -p ~/.openclaw/skills/agent-forge
cp /tmp/openclaw-superagent/skills/agent-forge/SKILL.md ~/.openclaw/skills/agent-forge/SKILL.md

# Если есть references (шаблоны агентов)
mkdir -p ~/.openclaw/skills/agent-forge/references
cp /tmp/openclaw-superagent/skills/agent-forge/references/*.md ~/.openclaw/skills/agent-forge/references/ 2>/dev/null || true
```

**Режимы Agent Forge:**

| Режим | Когда | Шагов |
|-------|-------|-------|
| Создание скилла | Нужен новый навык | 11 |
| Создание агента | Нужен новый бот с личностью | 9 |
| Улучшение существующего | Скилл/агент работает, но надо лучше | 5 |

**Типы скиллов:** Workflow (пошаговый), Role (экспертная роль), Data-driven (данные), Гибрид.

**Типы агентов:** Полноценный рабочий (свой бот, память, скиллы), Специализированный (своя экосистема), Маска (топик-роль через systemPrompt).

### Шаг 21: Установить ru-text (опционально, рекомендуется)

**Что делает:** качество русского текста. Типографика, инфостиль, редактура, UX-тексты, деловая переписка. ~1044 правил, 7 доменов. Автоактивируется при русском тексте.

```bash
# Через ClawHub
openclaw skills install ru-text

# Или вручную
cd /tmp && git clone https://github.com/talkstream/ru-text.git
mkdir -p ~/.openclaw/skills/ru-text
cp /tmp/ru-text/skills/ru-text/SKILL.md ~/.openclaw/skills/ru-text/SKILL.md
cp -r /tmp/ru-text/skills/ru-text/references ~/.openclaw/skills/ru-text/references
```

**Почему ru-text важен для агентов:**
- Корректная типографика: «кавычки», тире, неразрывные пробелы
- Чистый инфостиль: без «является», «осуществлять», «в настоящее время»
- UX-тексты: «Отмена» вместо «Нет», структура ошибок
- Деловая переписка: без канцелярита

### Шаг 22: Симлинк скиллов в workspace агента

Чтобы агент имел доступ к скиллам при установке на тот же сервер:

```bash
# Если скиллы в ~/.openclaw/skills/, а агент в ~/.openclaw/agents/<id>/
# Вариант A: симлинк (рекомендуется)
ln -s ~/.openclaw/skills ~/.openclaw/agents/<agent-id>/agent/skills

# Вариант B: копия (если агент на другом сервере)
cp -r ~/.openclaw/skills/agent-doctor ~/.openclaw/agents/<agent-id>/agent/skills/
cp -r ~/.openclaw/skills/agent-forge ~/.openclaw/agents/<agent-id>/agent/skills/
cp -r ~/.openclaw/skills/ru-text ~/.openclaw/agents/<agent-id>/agent/skills/
```

⚠️ **Для удалённой установки** (сервер ≠ текущий): скопируй SKILL.md каждого скилла через SSH:
```bash
ssh user@host "mkdir -p ~/.openclaw/skills/agent-doctor ~/.openclaw/skills/agent-forge ~/.openclaw/skills/ru-text"
scp /tmp/openclaw-superagent/skills/agent-doctor/SKILL.md user@host:~/.openclaw/skills/agent-doctor/
scp /tmp/openclaw-superagent/skills/agent-forge/SKILL.md user@host:~/.openclaw/skills/agent-forge/
scp /tmp/ru-text/skills/ru-text/SKILL.md user@host:~/.openclaw/skills/ru-text/
scp -r /tmp/ru-text/skills/ru-text/references user@host:~/.openclaw/skills/ru-text/
```

---

---

## Часть 11: Предложить установку дополнительных скиллов

### 🛑 СТОП-ЧЕКПОИНТ

**НЕ ИДТИ ДАЛЬШЕ (smoke tests, мониторинг) пока:**
1. ❌ Не предложил пользователю скиллы
2. ❌ Не дождался ответа (или явного «не надо»)
3. ❌ Не установил выбранные скиллы

Это ОБЯЗАТЕЛЬНЫЙ шаг, а не опциональный. Если пользователь сказал «позже» или проигнорировал — ок, но предложить нужно всегда.

### ⚠️ Почему это важно

Без скиллов агент бесполезен. agent-doctor + agent-forge + ru-text — это минимум выживания. Остальные — реальная ценность. Если не предложить — пользователь получит голый сервер и разочаруется.

### Процедура

После разворота ОБЯЗАТЕЛЬНО:
1. Собрать каталог доступных скиллов с источника (титов-main или другой сервер)
2. Показать пользователю список с кратким описанием
3. Предложить установить нужные

### Как собрать список скиллов

Скиллы можно брать из любого источника — не только с титов-main. Универсальный способ:

```bash
# Собрать все скиллы из указанной директории на любом сервере
# Каждый скилл — это директория с SKILL.md внутри
# description берётся из YAML-фронтматтера (строка после "description:")

SRC="~/.openclaw/skills"  # путь к скиллам на сервере-источнике

echo "=== Доступные скиллы ==="
for skill_dir in $SRC/*/; do
  name=$(basename "$skill_dir")
  skillfile="${skill_dir}SKILL.md"
  if [ -f "$skillfile" ]; then
    desc=$(grep -m1 '^description:' "$skillfile" | sed 's/^description: *//' | tr -d '"' | cut -c1-100)
    echo "  $name — $desc"
  fi
done

# Также проверить plugin-skills (если есть)
for skill_dir in ~/.openclaw/plugin-skills/*/ 2>/dev/null; do
  name=$(basename "$skill_dir")
  skillfile="${skill_dir}SKILL.md"
  if [ -f "$skillfile" ]; then
    desc=$(grep -m1 '^description:' "$skillfile" | sed 's/^description: *//' | tr -d '"' | cut -c1-100)
    echo "  $name — $desc"
  fi
done

# Встроенные скиллы OpenClaw (системные)
echo ""
echo "=== Системные скиллы (встроены, доступны всегда) ==="
for skill_dir in $(npm root -g)/openclaw/skills/*/ 2>/dev/null; do
  name=$(basename "$skill_dir")
  skillfile="${skill_dir}SKILL.md"
  if [ -f "$skillfile" ]; then
    desc=$(grep -m1 '^description:' "$skillfile" | sed 's/^description: *//' | tr -d '"' | cut -c1-100)
    echo "  $name — $desc"
  fi
done
```

### ⚠️ Что НЕ показывать

NSI-специфичные скиллы (лежат на titov-nsi: analytics-pro, career-coach, data-bridge-pro, devops-remote, executive-search-ru, strat-session, devops-automation-pack, devops-fleet, devops-techarch, и др.) — **никогда не показывать другим пользователям.**

### Как показать пользователю

Сгруппировать скиллы по категориям и отправить кратким списком с описаниями.

**Обязательные (уже установлены):**
• agent-doctor — самодиагностика OpenClaw: память, кроны, конфиг, gateway, безопасность. 7 категорий + автофиксы
• agent-forge — создание и улучшение скиллов и агентов
• ru-text — качество русского текста: типографика, инфостиль, редактура

**DevOps:**
• server-connect — надёжное подключение к серверу с ретраями и диагностикой
• deploy-agent — развёртывание агентов на новых серверах под ключ
• docker-sandbox — Docker-песочницы для безопасного выполнения кода

**Аналитика:**
• advanced-embeddings — продвинутые эмбеддинги для архитектора и knowledge base
• analyst-evaluator — оценка компетенций аналитиков, GAP-анализ, планы развития
• deep-research — глубокое исследование тем с верификацией
• personal-embeddings — эмбеддинги для номенклатурной классификации

**Контент и дизайн:**
• frontend-design-ultimate — генерация сайтов: лендинги, портфолио, дашборды (React, Tailwind)
• landing-page-generator — высококонверсионные лендинги для продуктов
• simple-html-generator — быстрые HTML-страницы с автопубликацией
• powerpoint-pptx — создание и редактирование PowerPoint презентаций

**Голос:**
• openai-whisper — распознавание речи локально, без API-ключа

**Данные:**
• speaker-data-guardian — защита от потери данных: бэкапы, валидация, восстановление
• raglite — локальный RAG-кэш: индексация документов + поиск

**Системные (встроены в OpenClaw, доступны всегда):**
~50 скиллов: github, notion, weather, summarize, coding-agent, tmux, obsidian, browser-automation, voice-call, discord, slack, gog (Google), himalaya (email), spotify, skill-creator, clawhub и другие.

⚠️ Список выше — текущий снимок с титов-main. При добавлении новых скиллов они автоматически попадают в каталог.
NSI-специфичные скиллы исключены из списка.

### Как устанавливать скиллы (с верификацией)

1. Пользователь говорит «установи X»
2. Скопировать SKILL.md с сервера-источника → на сервер пользователя:
   ```bash
   ssh user@target "mkdir -p ~/.openclaw/skills/X"
   scp ~/.openclaw/skills/X/SKILL.md user@target:~/.openclaw/skills/X/
   ```
3. **ОБЯЗАТЕЛЬНО: проверить что агент ВИДИТ скилл после установки:**
   ```bash
   ssh user@target "
     echo '=== Проверка установки ==='
     ls ~/.openclaw/skills/X/SKILL.md && echo '✅ Файл скилла на месте'
     
     # Проверить все директории агентов — у каждого должен быть доступ
     for agent_dir in ~/.openclaw/agents/*/agent/skills/; do
       [ -d \"\$agent_dir\" ] && ls \"\${agent_dir}X/SKILL.md\" 2>/dev/null && echo \"✅ Агент \$(basename \$(dirname \$(dirname \$agent_dir))) видит скилл\" || echo \"❌ Агент \$(basename \$(dirname \$(dirname \$agent_dir))) НЕ видит скилл — нужен symlink\"
     done
     
     # Если агент не видит — удалить старые, создать ОДИН symlink на всю skills/
     for agent_dir in ~/.openclaw/agents/*/agent/; do
       [ -d \"\$agent_dir\" ] && rm -rf \"\${agent_dir}skills\" && ln -sf ~/.openclaw/skills \"\${agent_dir}skills\"
     done
     
     # Перезапустить для подхвата
     systemctl restart openclaw
   "
   ```
4. **Подтвердить пользователю:** «Скилл X установлен, агент его видит ✅»

**Типичная проблема:** индивидуальные симлинки не обновляются при добавлении нового скилла. Надёжнее удалить директорию skills/ в агенте и создать symlink на всю глобальную директорию:
```bash
rm -rf ~/.openclaw/agents/main/agent/skills
ln -sf ~/.openclaw/skills ~/.openclaw/agents/main/agent/skills
```
После этого любые новые скиллы в `~/.openclaw/skills/` автоматически станут доступны агенту.

⚠️ **Ошибка Кристины:** скиллы были скопированы в `~/.openclaw/skills/`, но агент в `~/.openclaw/agents/main/agent/` не имел symlink → не видел их. Всегда проверять и чинить доступ после установки.

---

## Часть 12: SMOKE TESTS (обязательно после разворота)

### ⚠️ Не хардкодить эндпоинты

API-эндпоинты типа `/api/status` могут отсутствовать или меняться. Не использовать их в smoke-тестах — полагаться ТОЛЬКО на:
- `curl http://127.0.0.1:18789/health` (всегда работает)
- `systemctl is-active` (всегда работает)
- `journalctl` (всегда работает)

Если health отвечает, а порт слушается — сервер жив. Не пытаться вызвать несуществующие эндпоинты.

### 🛑 Не зависать

Каждый curl-запрос — с `--max-time 5`. Если завис — не ждать, убивать процесс и ретраить.
Все тесты — не дольше 10 секунд суммарно. Если что-то не отвечает → залогировать и идти дальше.

После завершения всех шагов установки — ОБЯЗАТЕЛЬНО пройти полный цикл тестирования. Ничего не должно отвалиться.

### Тест 1: Сервисы живы

```bash
systemctl is-active openclaw && echo "✅ OpenClaw active" || echo "❌ OpenClaw dead"
systemctl is-enabled openclaw 2>/dev/null && echo "✅ OpenClaw enabled" || echo "⚠️ OpenClaw not enabled"
systemctl is-active ollama && echo "✅ Ollama active" || echo "❌ Ollama dead"
systemctl is-enabled ollama && echo "✅ Ollama enabled" || echo "⚠️ Ollama not enabled"
```

### Тест 2: Ollama API — все модели работают

```bash
# Проверить КАЖДУЮ модель
for model in deepseek-v4-pro:cloud glm-5.1:cloud kimi-k2.6:cloud; do
  echo "=== $model ===" && curl -s http://127.0.0.1:11434/api/chat \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}],\"stream\":false,\"max_tokens\":5}" \
    --max-time 25 | python3 -c "import sys,json; d=json.load(sys.stdin); print('✅', d['message']['content'])" 2>&1
done

# Проверить эмбеддинги
curl -s http://127.0.0.1:11434/api/embed \
  -d '{"model":"nomic-embed-text:latest","input":"test"}' \
  --max-time 10 | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'✅ Embeddings: {len(d[\"embeddings\"][0])}d')" 2>&1
```

### Тест 3: Ollama API ключ в ТРЁХ местах (ранее двух)

```bash
# Проверить в systemd сервисе Ollama (для ollama CLI)
cat /etc/systemd/system/ollama.service.d/api-key.conf 2>/dev/null | grep OLLAMA_API_KEY && echo "✅ API key in ollama systemd" || echo "❌ MISSING in ollama systemd — cloud models WILL FAIL after restart"

# Проверить в systemd сервисе OpenClaw (для runtime)
grep OLLAMA_API_KEY /etc/systemd/system/openclaw.service.d/*.conf 2>/dev/null && echo "✅ API key in openclaw systemd" || echo "ℹ️ Not in openclaw systemd (will use .env)"

# Проверить в .env OpenClaw (основной путь)
grep OLLAMA_API_KEY /root/.openclaw/.env 2>/dev/null && echo "✅ API key in openclaw .env" || echo "❌ MISSING in openclaw .env"

# Проверить в конфиге OpenClaw (OpenClaw передаёт ключ в запросах к Ollama)
python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json') as f:
    d = json.load(f)
providers = d.get('models',{}).get('providers',{})
for v in providers.values():
    if v.get('api') == 'ollama' and v.get('apiKey'):
        key_len = len(v.get('apiKey',''))
        print(f'✅ API key in OpenClaw config ({key_len} chars)'); break
else:
    print('❌ No API key in OpenClaw config')
"
```

**Почему три места:**
1. systemd ollama — для `ollama pull` и `ollama run`
2. systemd/`.env` openclaw — для runtime OpenClaw
3. openclaw.json `models.providers.ollama.apiKey` — OpenClaw передаёт этот ключ в каждом запросе к Ollama

Если хотя бы в одном месте ключ отсутствует — модели не заработают.

### Тест 4: OpenClaw слушает порт

```bash
ss -tlnp | grep 18789 && echo "✅ OpenClaw listening" || echo "❌ NOT listening"
```

### Тест 5: Telegram бот валиден

```bash
BOT_TOKEN=$(python3 -c "import json; d=json.load(open('$HOME/.openclaw/openclaw.json')); print(d['channels'][0]['botToken'])" 2>/dev/null || python3 -c "import json; d=json.load(open('$HOME/.openclaw/openclaw.json')); print(d['channels']['telegram']['accounts']['default']['botToken'])" 2>/dev/null)
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d.get('ok'): print('✅ Bot:', d['result']['username'])
else: print('❌ Invalid token:', d.get('description'))
"
```

### Тест 6: Логи без ошибок

```bash
journalctl -u openclaw --no-pager -n 50 | grep -iE "error|fatal" | tail -5 || echo "✅ No errors"
journalctl -u ollama --no-pager -n 20 | grep -iE "error|fatal" | tail -5 || echo "✅ No Ollama errors"
```

### 🆕 Тест 7: Cross-Model Validation (двойная проверка)

**Критично для чужих серверов.** Каждое действие проверяется ДВУМЯ разными моделями:
- Primary модель выполняет задачу
- Fallback модель независимо проверяет результат
- Если ответы расходятся → алерт

```bash
# Проверяем что обе модели дают согласованный ответ на один и тот же запрос
PRIMARY="deepseek-v4-pro:cloud"
FALLBACK="glm-5.1:cloud"
TEST_PROMPT="What is 2+2? Answer with just the number."

# Primary
R1=$(curl -s http://127.0.0.1:11434/api/chat -d "{\"model\":\"$PRIMARY\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEST_PROMPT\"}],\"stream\":false,\"max_tokens\":10}" | python3 -c "import sys,json; print(json.load(sys.stdin)['message']['content'].strip())" 2>/dev/null)

# Fallback
R2=$(curl -s http://127.0.0.1:11434/api/chat -d "{\"model\":\"$FALLBACK\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEST_PROMPT\"}],\"stream\":false,\"max_tokens\":10}" | python3 -c "import sys,json; print(json.load(sys.stdin)['message']['content'].strip())" 2>/dev/null)

echo "Primary ($PRIMARY): $R1"
echo "Fallback ($FALLBACK): $R2"

if echo "$R1" | grep -q "4" && echo "$R2" | grep -q "4"; then
    echo "✅ Cross-model validation PASSED — both models agree"
else
    echo "❌ Cross-model validation FAILED — models disagree, investigation needed"
fi
```

### Тест 8: Комплексный E2E тест (бот отвечает через разные модели)

```bash
# Проверить что бот отвечает и что primary + fallback работают в бою
# Отправить тестовое сообщение боту через Telegram API
BOT_TOKEN=$(python3 -c "
import json
with open(\"$HOME/.openclaw/openclaw.json\") as f:
    d = json.load(f)
for c in d['channels']:
    print(c.get('botToken',''))
" 2>/dev/null)

# Проверить конфиг агента — primary и fallbacks прописаны
python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json') as f:
    d = json.load(f)
agents = d.get('agents',{})
for k,v in agents.items():
    model = v.get('model',{})
    if isinstance(model, dict):
        print(f'Agent {k}:')
        print(f'  Primary: {model.get(\"primary\",\"?\")}')
        fallbacks = model.get('fallbacks',[])
        if fallbacks:
            print(f'  Fallbacks: {fallbacks}')
            print('✅ Multi-model configured')
        else:
            print('⚠️ No fallbacks — single point of failure')
"
```

---

## Часть 13: 7-DAY MONITORING

После успешного разворота настроить автоматический мониторинг на 7 дней.

### Deploy healthcheck скрипт

Создать на сервере:

```bash
cat > /usr/local/bin/openclaw-healthcheck.sh << 'EOF'
#!/bin/bash
LOG=/var/log/openclaw-healthcheck.log
date >> $LOG

# 1. OpenClaw alive?
if ! systemctl is-active --quiet openclaw; then
    echo "❌ OpenClaw dead — restarting" >> $LOG
    systemctl restart openclaw
fi

# 2. Ollama alive?
if ! systemctl is-active --quiet ollama; then
    echo "❌ Ollama dead — restarting" >> $LOG
    systemctl restart ollama
fi

# 3. API key present in ALL THREE places? (CRITICAL for cloud models)
MISSING_KEYS=""
if ! grep -q OLLAMA_API_KEY /etc/systemd/system/ollama.service.d/api-key.conf 2>/dev/null; then
    MISSING_KEYS="$MISSING_KEYS ollama-systemd"
fi
if ! grep -q OLLAMA_API_KEY /root/.openclaw/.env 2>/dev/null; then
    MISSING_KEYS="$MISSING_KEYS openclaw-env"
fi
if ! python3 -c "
import json
with open('/root/.openclaw/openclaw.json') as f:
    d = json.load(f)
for v in d.get('models',{}).get('providers',{}).values():
    if v.get('api')=='ollama' and v.get('apiKey'):
        exit(0)
exit(1)
" 2>/dev/null; then
    MISSING_KEYS="$MISSING_KEYS openclaw-json"
fi
if [ -n "$MISSING_KEYS" ]; then
    echo "❌ OLLAMA_API_KEY MISSING in:$MISSING_KEYS" >> $LOG
fi

# 4. Port listening?
if ! ss -tlnp | grep -q 18789; then
    echo "❌ Port 18789 not listening — restarting OpenClaw" >> $LOG
    systemctl restart openclaw
fi

# 5. Gateway error-free?
ERRORS=$(journalctl -u openclaw --since "30 min ago" -n 30 | grep -ciE "error|fatal" || true)
if [ "$ERRORS" -gt 3 ]; then
    echo "⚠️ $ERRORS errors in gateway log" >> $LOG
fi

echo "✅ OK" >> $LOG
EOF

chmod +x /usr/local/bin/openclaw-healthcheck.sh

# Cron every 30 min for 7 days
(crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/openclaw-healthcheck.sh") | crontab -
```

### Remove after 7 days

```bash
crontab -l | grep -v openclaw-healthcheck | crontab -
rm /usr/local/bin/openclaw-healthcheck.sh
```

### ⚠️ OLLAMA_API_KEY — самая частая причина отвала

Ключ должен быть в **ТРЁХ** местах:
1. `/etc/systemd/system/ollama.service.d/api-key.conf` → `Environment="OLLAMA_API_KEY=..."` (для ollama CLI)
2. `/root/.openclaw/.env` → `OLLAMA_API_KEY=...` (для runtime OpenClaw)
3. `~/.openclaw/openclaw.json` → `models.providers.ollama.apiKey` (OpenClaw передаёт ключ в запросах к Ollama)

Если ключ пропадёт из любого из мест → облачные модели отвалятся.
Мониторинг проверяет все три места каждые 30 минут.

---

## Чеклист (полный, с тестами)

- [ ] SSH доступ работает
- [ ] Система обновлена, таймзона правильная
- [ ] Node.js установлен (v24+)
- [ ] OpenClaw установлен и gateway запущен
- [ ] Ollama установлена и работает
- [ ] Cloud-модели скачаны (ollama list)
- [ ] nomic-embed-text скачан
- [ ] memorySearch настроен
- [ ] Память: memory/, MEMORY.md, MEMORY-POLICY.md
- [ ] Telegram-токен получен
- [ ] Workspace агента создан
- [ ] Агент + аккаунт + binding в конфиге
- [ ] Gateway перезапущен
- [ ] Бот отвечает в Telegram
- [ ] Agent Doctor + Agent Forge + ru-text установлены
- [ ] ✅ SMOKE TESTS ПРОЙДЕНЫ (7 тестов)
- [ ] ✅ API ключ проверен ДО развёртывания (Шаг 00)
- [ ] ✅ 7-day monitoring настроен
- [ ] ✅ Данные записаны в MEMORY.md + SECRETS.md
- [ ] ✅ server-connect диагностика выполнена

---

## Безопасность

- Все токены и пароли — в SECRETS.md DevOps-агента (НЕ в TOOLS.md, НЕ в память агента)
- После разворота: записать в MEMORY.md (секция владельца) + SECRETS.md (пароли)
- Никогда не показывать пароли в чат
- Данные владельцев не смешивать
