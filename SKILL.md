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

## 🛡️ Часть -1: Защита сессии и атомарность данных

**Почему это здесь, ДО начала работы:** кейс Елены Банновой (2026-06-04). Сессия упала 2 раза в процессе развёртывания:
- После получения SSH и API-ключа — сессия упала, данные потеряны
- После получения токена бота — в конфиг попал плейсхолдер (11 символов вместо 46)
- Пришлось переспрашивать данные → плохой UX, потеря доверия

**Правила, которые предотвращают это:**

### Правило 0.1: Save-Game МГНОВЕННО

**Получил любые credentials от человека → в том же ходе записал в файлы. Без исключений.**

Порядок записи (строгий):
1. Сначала SECRETS.md (grep по имени, update секции)
2. Потом MEMORY.md (update секции владельца)
3. Только потом — продолжать развёртывание

**Почему сначала SECRETS.md:** если сессия упадёт на MEMORY.md, credentials уже сохранены.

```bash
# Пример: получил SSH от Елены
# 1. Сразу пишем в SECRETS.md (через edit/write в workspace)
# 2. Сразу пишем в MEMORY.md
# 3. Только потом идём на сервер
```

### Правило 0.2: Верификация токенов

**После записи токена в конфиг — ПРОВЕРИТЬ что он валидный.**

```bash
# Проверка длины Telegram-токена (должен быть 46 символов: 10 цифр + двоеточие + 35 символов)
TOKEN=$(python3 -c "import json; c=json.load(open('/root/.openclaw/openclaw.json')); print(len(c['channels']['telegram']['botToken']))")
if [ "$TOKEN" -lt 40 ]; then
  echo "❌ Токен обрезан! Длина: $TOKEN (должно быть ~46). НЕ перезапускать сервис."
  # Срочно запросить полный токен у пользователя
  exit 1
fi
echo "✅ Токен валидной длины: $TOKEN символов"

# Проверка API-ключа Ollama Cloud (должен быть ~50+ символов)
KEY_LEN=$(python3 -c "import json; c=json.load(open('/root/.openclaw/openclaw.json')); print(len(c['models']['providers'].get('ollama-cloud',{}).get('apiKey','')))")
if [ "$KEY_LEN" -lt 30 ]; then
  echo "❌ API-ключ обрезан! Длина: $KEY_LEN (должно быть 50+). НЕ перезапускать сервис."
  exit 1
fi
echo "✅ API-ключ валидной длины: $KEY_LEN символов"
```

### Правило 0.3: Контрольные точки (Checkpoints)

**Фиксировать прогресс в MEMORY.md после каждого крупного шага.**

Формат checkpoint-записи:
```markdown
## 🚧 Deploy {имя}: Checkpoint {N}/{total}
- Статус: {step completed}
- Следующий шаг: {next step}
- Данные получены: SSH ✅ | API Key ✅ | Bot Token ⬜
- Последнее действие: {timestamp}
```

При падении сессии — поискать `🚧 Deploy` в MEMORY.md и продолжить с последнего checkpoint.

**Checkpoints (минимальный набор):**
| # | Когда | Что зафиксировать |
|---|-------|-------------------|
| CP1 | Получили SSH | Хост, пользователь (без пароля) |
| CP2 | Получили API-ключ | Тип ключа, провайдер (без самого ключа) |
| CP3 | Получили токен бота | @username бота, id бота (без токена) |
| CP4 | SSH подключение успешно | Версия ОС, RAM, диск |
| CP5 | Node.js установлен | Версия node |
| CP6 | OpenClaw установлен | Версия, статус gateway |
| CP7 | Ollama + модели | Список моделей |
| CP8 | Конфиг написан | Длина токена проверена ✅ |
| CP9 | Бот отвечает | Telegram API getMe OK |
| CP10 | Готово | Итоговый статус |

### Правило 0.4: Сессия-убийца

**Если сессия падает 2 раза на одном и том же пользователе:**
1. НЕ продолжать в этой же сессии
2. Сбросить сессию: `rm -rf ~/.openclaw/agents/devops/sessions/agent:devops:telegram:direct:{user_id}*`
3. Начать в свежей сессии (новое сообщение от пользователя создаст чистую)
4. Восстановить состояние из checkpoint в MEMORY.md

### Правило 0.6: НИКОГДА не слать пользователю сырые ошибки

**Кейс Елены: бот трижды повторил «Something went wrong while processing your request...» — пользователь в шоке, не понимает что делать.**

**Что делать ВМЕСТО этого:**

1. **Поймал ошибку → НЕ пересылать её пользователю как есть.** Технические сообщения типа «Something went wrong», «404 Not Found», stack traces — только в лог, никогда в чат.

2. **Отправить ОДНО человеческое сообщение:**
   - Что случилось простыми словами
   - Что я уже делаю чтобы исправить
   - Через сколько вернусь (примерно)
   - Что делать пользователю (обычно — ничего, ждать)

3. **Шаблоны сообщений об ошибках:**

**При потере сессии (самая опасная):**
```
⚠️ Технический сбой на моей стороне. Данные сохранены, я уже восстанавливаюсь.
Напиши любое сообщение через 2-3 минуты — я продолжу с того же места.
```

**При ошибке валидации токена/ключа:**
```
❌ Токен невалидный — возможно обрезался при копировании. 
Проверь его в @BotFather: /mybots → {имя бота} → API Token.
Скопируй токен целиком и пришли ещё раз.
```

**При ошибке подключения к серверу:**
```
🔌 Не могу подключиться к серверу. Проверяю...
[через 30 сек]
Нашёл проблему: {что именно}. {Что делаю}.
```

**При любой другой ошибке:**
```
⚠️ Что-то пошло не так на шаге «{шаг}». 
Я уже работаю над исправлением. Напишу через минуту.
```

**Правило «одно сообщение»:**
- ❌ НЕ слать несколько сообщений подряд с ошибками
- ❌ НЕ повторять одно и то же сообщение (как на скриншоте Елены — 3 раза)
- ✅ Одно сообщение → пауза → исправление → результат
- Если не можешь исправить за 2 минуты → напиши «всё ещё работаю, ещё 5 минут»

### Правило 0.7: Таймаут на каждый шаг

**Каждый внешний вызов — с таймаутом. Никаких бесконечных ожиданий.**

```bash
# SSH — 10 секунд на подключение
ssh -o ConnectTimeout=10 ...

# curl — 15 секунд максимум
curl --max-time 15 ...

# systemctl — 5 секунд
systemctl restart openclaw && sleep 5
```

Если таймаут истёк — не повторять бесконечно. Сообщить пользователю и перейти к диагностике.

### Правило 0.5: Dry-Run конфига перед рестартом

**Перед `systemctl restart openclaw` — проверить валидность JSON:**

```bash
python3 -c "import json; json.load(open('/root/.openclaw/openclaw.json'))" && echo "✅ JSON valid" || echo "❌ JSON broken — DO NOT RESTART"
```

Битый JSON при рестарте = сервис не поднимется. Всегда проверять.

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

### 🆕 Шаг 00: Валидация API ключа и токенов ДО развёртывания

**КРИТИЧНО: проверять API ключ и токены сразу после получения, до любых других действий.**

Это предотвращает две катастрофические ситуации:
- «Всё развернули, а ключ не работает»
- «Токен бота обрезан, бот падает в crash-луп, пользователь ждёт» (кейс Елены)

#### Проверка API-ключа Ollama Cloud

```bash
# Проверить ключ на СВОЁМ сервере (на титов-main):
# Это работает даже если целевой сервер ещё не готов
curl -s --max-time 15 http://127.0.0.1:11434/api/chat \
  -H "Authorization: Bearer {API_KEY}" \
  -d '{"model":"deepseek-v4-pro:cloud","messages":[{"role":"user","content":"Say hi"}],"stream":false,"max_tokens":5}'

# Если ответ — 401 unauthorized → ключ НЕВЕРНЫЙ, просить новый
# Если ответ содержит "message" → ключ рабочий ✅, можно продолжать
```

#### Проверка Telegram-токена (ОБЯЗАТЕЛЬНАЯ)

**Кейс Елены: токен был обрезан до 11 символов. Результат: бот падал в crash-луп, пользователь ждал.**

```bash
# Сразу после получения токена — проверить его через Telegram API
# Это можно сделать с ЛЮБОГО сервера, не только с целевого
curl -s --max-time 10 "https://api.telegram.org/bot{TOKEN}/getMe"

# Ожидаемый ответ: {"ok":true,"result":{"id":...,"username":"..."}}
# Если ok:false или 404 — токен невалидный или обрезан

# Проверить длину токена (должен быть ~46 символов)
echo -n "{TOKEN}" | wc -c
# < 40 символов → ОБРЕЗАН! Запросить полный токен у пользователя
```

**Формат валидного Telegram-токена:** `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz-1234567`
- 10 цифр (bot id) + двоеточие + 35 символов (secret) = 46 символов
- Если прислали `883086…NrXs` (11 символов с троеточием) — это обрезанный токен, НЕ использовать

#### После записи токена в конфиг — верификация на целевом сервере

```bash
# После записи в openclaw.json — проверить длину из конфига
python3 -c "
import json
with open('/root/.openclaw/openclaw.json') as f:
    c = json.load(f)
token = c['channels']['telegram']['botToken']
print(f'Token length: {len(token)}')
assert len(token) >= 40, f'TOKEN TOO SHORT: {len(token)} chars!'
print('✅ Token length OK')
"
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

### Шаг 11: Создание структуры памяти (Memory Blueprint)

**Использовать архитектуру Memory Blueprint** (`~/.openclaw/skills/memory-blueprint/SKILL.md`):

```bash
# Директория памяти
mkdir -p ~/.openclaw/workspace/memory

# Файл основной памяти
cat > ~/.openclaw/workspace/MEMORY.md << 'EOF'
# MEMORY.md — {DISPLAY_NAME}

## Сервер
- Хост: {host}
- OpenClaw: {version}
- Модель: {model}
- Развёрнут: {date}
EOF

# Все memory-файлы по Memory Blueprint
touch ~/.openclaw/workspace/memory/lessons.md
touch ~/.openclaw/workspace/memory/patterns.md
touch ~/.openclaw/workspace/memory/projects-log.md
touch ~/.openclaw/workspace/memory/handoff.md

# Контракт памяти
cp ~/.openclaw/skills/memory-blueprint/references/contract-template.md \
   ~/.openclaw/workspace/memory/contract.md

# Первый daily entry
cat > ~/.openclaw/workspace/memory/$(date +%Y-%m-%d).md << EOF
# $(date +%Y-%m-%d) — Развёртывание

- Агент развёрнут и подключён к Telegram
- Модель: {model}
- Сервер: {host}
EOF
```

### Шаг 12: Memory Blueprint в AGENTS.md

В AGENTS.md агента **обязательно** добавить секцию памяти из шаблона:

```bash
cat >> ~/.openclaw/workspace-{agent_id}/AGENTS.md << 'EOF'

## 🧠 Память (Memory Blueprint)

Архитектура памяти: 4 уровня (контекстная → файловая → векторная → identity).

**Контракт:** `memory/contract.md` — что хранить и чего не хранить (Keep/Delete/Rewrite/Limit).

### Файлы памяти
| Файл | Назначение |
|------|-----------|
| `memory/lessons.md` | Уроки и правила |
| `memory/patterns.md` | Паттерны (3 повтора → правило) |
| `memory/projects-log.md` | История задач |
| `memory/handoff.md` | Save-game разговора |
| `memory/YYYY-MM-DD.md` | Дневник дня |

### При старте
1. `memory/handoff.md` — контекст предыдущей сессии
2. `memory/YYYY-MM-DD.md` — дневник сегодня

### При ошибках
- Записать в `memory/lessons.md`
- 3 повтора → паттерн в `memory/patterns.md`

### Еженедельный аудит
- `memory/contract.md` → проверить лимиты
- MEMORY.md ≤ 300 строк
- Удалить дневники >90 дней
- Проверить на утечку credentials
EOF
```

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
См. `memory/contract.md` — Memory Blueprint (Keep/Delete/Rewrite/Limit).
При старте: читать `memory/handoff.md` и `memory/YYYY-MM-DD.md`.

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
  "workspace": "~/.openclaw/workspace-{agent_id}"
}
```
⚠️ Модель НЕ указывать здесь — она наследуется из agents.defaults.model (deepseek + glm fallback).

Если нужна другая модель для конкретного агента:
```json
"model": {
  "primary": "ollama/deepseek-v4-pro:cloud",
  "fallbacks": ["ollama/glm-5.1:cloud"]
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

**Настройка fallback (стандарт Memory Blueprint):**
```json
"model": {
  "primary": "ollama/deepseek-v4-pro:cloud",
  "fallbacks": ["ollama/glm-5.1:cloud"]
}
```
⚠️ По умолчанию используем именно эту связку (deepseek + glm) — зафиксировано в memory-blueprint скилле.

**Если нужен второй fallback (kimi):**
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
- [ ] Структура памяти создана (memory/*.md, MEMORY.md, memory/contract.md)
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

### Шаг 19: Установить обязательные скиллы (единый механизм)

**Все скиллы устанавливаются одним способом — `scp` с сервера-источника (titov-main). Никаких git clone, никакого ClawHub.**

Обязательные скиллы (устанавливаются всегда, без спроса):
- **agent-doctor** — самодиагностика (7 категорий + автофиксы)
- **agent-forge** — создание скиллов и агентов (3 режима)
- **ru-text** — качество русского текста (~1044 правила, 7 доменов)

```bash
# Единый механизм установки скиллов
SOURCE="root@162.248.164.75"  # titov-main
TARGET="root@${TARGET_IP}"    # сервер пользователя

# Список обязательных скиллов
REQUIRED_SKILLS="agent-doctor agent-forge ru-text"

install_skill() {
  local skill=$1
  local src=$2
  local dst=$3
  
  echo "=== Установка: $skill ==="
  
  # 1. Создать директорию
  ssh $dst "mkdir -p ~/.openclaw/skills/$skill"
  
  # 2. Скопировать SKILL.md
  scp ~/.openclaw/skills/$skill/SKILL.md ${dst}:~/.openclaw/skills/$skill/SKILL.md
  
  # 3. Скопировать references если есть
  ssh $src "[ -d ~/.openclaw/skills/$skill/references ]" && \
    ssh $dst "mkdir -p ~/.openclaw/skills/$skill/references" && \
    scp -r ~/.openclaw/skills/$skill/references/* ${dst}:~/.openclaw/skills/$skill/references/ 2>/dev/null || true
  
  # 4. Верификация: файл существует и не пустой
  if ssh $dst "[ -s ~/.openclaw/skills/$skill/SKILL.md ]"; then
    SIZE=$(ssh $dst "wc -c < ~/.openclaw/skills/$skill/SKILL.md")
    echo "  ✅ Скилл $skill установлен ($SIZE байт)"
  else
    echo "  ❌ ОШИБКА: скилл $skill не установился"
    return 1
  fi
}

# Установить все обязательные скиллы
FAILED=""
for skill in $REQUIRED_SKILLS; do
  if ! install_skill "$skill" "$SOURCE" "$TARGET"; then
    FAILED="$FAILED $skill"
  fi
done

if [ -n "$FAILED" ]; then
  echo "❌ Не удалось установить:$FAILED"
  echo "Проверь подключение к серверу-источнику"
  exit 1
fi

echo "✅ Все обязательные скиллы установлены"
```

### Шаг 20: Симлинк + трехуровневая валидация + откат

**После копирования скиллов — обязательно проверить что агент их реально видит. Просто «файл есть» ≠ «агент может использовать».**

Кейс Кристины: скиллы скопированы в `~/.openclaw/skills/` ✅, но symlink в агенте отсутствовал ❌ → агент их не видел.

Три уровня валидации:
1. **Уровень файла:** SKILL.md существует, > 100 байт, содержит `description:` (не мусор)
2. **Уровень symlink:** агент видит файл через `~/.openclaw/agents/{id}/agent/skills/{skill}/SKILL.md`
3. **Уровень агента:** после рестарта — проверить что агент загрузил скилл (по логам)

```bash
ssh $TARGET "
echo '==========================================='
echo ' ВАЛИДАЦИЯ СКИЛЛОВ: 3 УРОВНЯ'
echo '==========================================='

SKILLS_DIR=\$HOME/.openclaw/skills
REQUIRED_SKILLS='agent-doctor agent-forge ru-text'

# ─── УРОВЕНЬ 1: Валидация файлов ───
echo ''
echo '─── Уровень 1: Валидация SKILL.md ───'

FAILED_FILES=''

for skill in \$REQUIRED_SKILLS; do
  SKILL_FILE=\"\$SKILLS_DIR/\$skill/SKILL.md\"
  
  # Проверка 1: файл существует
  if [ ! -f \"\$SKILL_FILE\" ]; then
    echo \"  ❌ \$skill: файл не существует\"
    FAILED_FILES=\"\$FAILED_FILES \$skill\"
    continue
  fi
  
  # Проверка 2: размер > 100 байт (не пустой и не мусор)
  SIZE=\$(wc -c < \"\$SKILL_FILE\")
  if [ \"\$SIZE\" -lt 100 ]; then
    echo \"  ❌ \$skill: файл слишком маленький (\$SIZE байт, минимум 100)\"
    FAILED_FILES=\"\$FAILED_FILES \$skill\"
    continue
  fi
  
  # Проверка 3: содержит description: (признак валидного SKILL.md)
  if ! grep -q 'description:' \"\$SKILL_FILE\"; then
    echo \"  ❌ \$skill: файл не содержит description: — это не SKILL.md\"
    FAILED_FILES=\"\$FAILED_FILES \$skill\"
    continue
  fi
  
  echo \"  ✅ \$skill: \$SIZE байт, description: OK\"
done

if [ -n \"\$FAILED_FILES\" ]; then
  echo ''
  echo \"❌ УРОВЕНЬ 1 ПРОВАЛЕН: битые скиллы:\$FAILED_FILES\"
  echo 'Выполняю откат...'
  for skill in \$FAILED_FILES; do
    rm -rf \"\$SKILLS_DIR/\$skill\"
    echo \"  🗑 Удалён битый скилл: \$skill\"
  done
  echo '⚠️ НЕ перезапускать сервис с битыми скиллами!'
  exit 1
fi

echo '✅ Уровень 1 пройден: все SKILL.md валидны'

# ─── УРОВЕНЬ 2: Валидация symlink ───
echo ''
echo '─── Уровень 2: Symlink в агентах ───'

# Создать symlink для каждого агента
for agent_dir in \$HOME/.openclaw/agents/*/agent/; do
  [ -d \"\$agent_dir\" ] || continue
  agent_name=\$(basename \$(dirname \$agent_dir))
  
  # Удалить старую директорию или битый symlink
  rm -rf \"\${agent_dir}skills\"
  
  # Создать symlink на глобальную директорию
  ln -sf \$SKILLS_DIR \"\${agent_dir}skills\"
  
  echo \"  🔗 \$agent_name: symlink создан\"
done

# Проверить что symlink работает для каждого агента и каждого скилла
LINK_FAILED=''

for agent_dir in \$HOME/.openclaw/agents/*/agent/skills/; do
  [ -d \"\$agent_dir\" ] || continue
  agent_name=\$(basename \$(dirname \$(dirname \$agent_dir)))
  
  for skill in \$REQUIRED_SKILLS; do
    AGENT_SKILL=\"\${agent_dir}\${skill}/SKILL.md\"
    
    if [ -f \"\$AGENT_SKILL\" ]; then
      echo \"  ✅ \$agent_name видит \$skill\"
    else
      echo \"  ❌ \$agent_name НЕ видит \$skill → symlink битый!\"
      LINK_FAILED=\"\$LINK_FAILED \$agent_name:\$skill\"
    fi
  done
done

if [ -n \"\$LINK_FAILED\" ]; then
  echo ''
  echo \"❌ УРОВЕНЬ 2 ПРОВАЛЕН: битые symlink:\$LINK_FAILED\"
  echo 'Выполняю откат: пересоздаю symlink...'
  
  for agent_dir in \$HOME/.openclaw/agents/*/agent/; do
    [ -d \"\$agent_dir\" ] || continue
    agent_name=\$(basename \$(dirname \$agent_dir))
    rm -rf \"\${agent_dir}skills\"
    ln -sf \$SKILLS_DIR \"\${agent_dir}skills\"
    
    # Проверить снова
    for skill in \$REQUIRED_SKILLS; do
      if [ -f \"\${agent_dir}skills/\${skill}/SKILL.md\" ]; then
        echo \"  🔧 \$agent_name:\$skill — исправлено\"
      else
        echo \"  💀 \$agent_name:\$skill — НЕ ИСПРАВЛЯЕТСЯ, ручное вмешательство\"
        exit 1
      fi
    done
  done
fi

echo '✅ Уровень 2 пройден: все агенты видят все скиллы через symlink'
"

# ─── УРОВЕНЬ 3: Валидация после рестарта ───
echo ''
echo '─── Уровень 3: Проверка после рестарта ───'

# Перезапустить OpenClaw
ssh $TARGET "systemctl restart openclaw"
sleep 5

# Проверить что сервис жив
SERVICE_STATUS=$(ssh $TARGET "systemctl is-active openclaw")
if [ "$SERVICE_STATUS" != "active" ]; then
  echo "❌ УРОВЕНЬ 3 ПРОВАЛЕН: сервис не запустился после установки скиллов!"
  echo "Смотрим логи:"
  ssh $TARGET "journalctl -u openclaw --since '10 sec ago' --no-pager | tail -20"
  echo ''
  echo 'Выполняю откат: удаляю все установленные скиллы, рестартую заново'
  ssh $TARGET "
    for skill in $REQUIRED_SKILLS; do
      rm -rf \$HOME/.openclaw/skills/\$skill
    done
    systemctl restart openclaw
  "
  echo '⚠️ Установка скиллов ОТМЕНЕНА. Сервис восстановлен без скиллов.'
  exit 1
fi

# Проверить что агент загрузил скиллы (по логам)
SKILL_LOG=$(ssh $TARGET "journalctl -u openclaw --since '10 sec ago' --no-pager 2>&1 | grep -c 'skill.*loaded\|loading skill' || echo 0")
echo "  📋 Скиллов загружено (по логам): $SKILL_LOG"

if [ "$SKILL_LOG" -ge 1 ]; then
  echo '✅ Уровень 3 пройден: сервис жив, скиллы загружены'
else
  echo '⚠️ Сервис жив, но скиллы не обнаружены в логах — возможно logging level не показывает загрузку скиллов'
  echo 'Это не ошибка, продолжаем'
fi

echo ''
echo '==========================================='
echo ' ✅ ВСЕ 3 УРОВНЯ ПРОЙДЕНЫ'
echo '==========================================='
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

### Как собирать каталог

**Источник:** `~/.openclaw/skills/` на titov-main. Каталог собирается динамически — не захардкожен.

```bash
# Собрать все скиллы с titov-main
ssh user@titov-main "
  echo '=== Доступные скиллы ==='
  for skill_dir in ~/.openclaw/skills/*/; do
    name=\$(basename \"\$skill_dir\")
    skillfile=\"\${skill_dir}SKILL.md\"
    if [ -f \"\$skillfile\" ]; then
      desc=\$(grep -m1 '^description:' \"\$skillfile\" | sed 's/^description: *//' | tr -d '\"' | head -c 80)
      echo \"  \$name — \$desc\"
    fi
  done
"
```

### Как показывать пользователю

Сгруппировать скиллы по категориям и отправить кратким списком с описаниями.

**Обязательные (уже установлены):** всегда показывать первыми, не предлагать удалять

**Остальные:** сгруппировать по категориям. Каждая категория с заголовком, каждый скилл одной строкой.

Пример вывода (генерируется из реального списка на titov-main):

```
📦 Доступные скиллы (с titov-main):

✅ Уже установлены:
• agent-doctor — самодиагностика
• agent-forge — создание скиллов
• ru-text — качество русского текста

🛠 DevOps:
• server-connect — подключение к серверам
• deploy-agent — развёртывание агентов
• docker-sandbox — Docker-песочницы

📊 Аналитика:
• advanced-embeddings — эмбеддинги
• analyst-evaluator — оценка компетенций
• deep-research — исследование тем

🎨 Дизайн:
• frontend-design-ultimate — сайты
• landing-page-generator — лендинги
• simple-html-generator — HTML-страницы
• powerpoint-pptx — презентации
• diagram-maker — диаграммы

🎤 Голос:
• openai-whisper — распознавание речи

💾 Данные:
• speaker-data-guardian — бэкапы
• raglite — RAG-кэш

Напиши какие установить (например: «установи server-connect, docker-sandbox»), или «все» чтобы установить всё, или «пропусти» чтобы оставить только обязательные.
```

### ⚠️ Правила показа

1. **Не ставить ничего без спроса.** Даже если кажется что «точно пригодится» — показать и ждать ответа
2. **Ждать ответа.** Не продолжать развёртывание пока пользователь не ответит
3. **Если пользователь сказал «позже» или «пропусти» — не настаивать**, оставить только обязательные
4. **Если пользователь сказал «все» — установить всё из каталога (кроме обязательных, они уже есть)**
5. **Если пользователь назвал конкретные скиллы — установить только их**

### Как устанавливать выбранные скиллы

```bash
# SKILLS_TO_INSTALL="server-connect docker-sandbox" (получено от пользователя)
# SOURCE_SERVER="titov-main" (или другой сервер-источник)

for skill in $SKILLS_TO_INSTALL; do
  echo "=== Установка скилла: $skill ==="
  
  # 1. Скопировать с сервера-источника
  scp root@${SOURCE_SERVER}:~/.openclaw/skills/${skill}/SKILL.md root@${TARGET}:~/.openclaw/skills/${skill}/
  
  # 2. Проверить что файл скопирован и не пустой
  ssh root@${TARGET} "
    if [ -s ~/.openclaw/skills/${skill}/SKILL.md ]; then
      echo '✅ Скилл ${skill} скопирован'
    else
      echo '❌ ОШИБКА: скилл ${skill} не скопировался или пустой'
      exit 1
    fi
  " || {
    echo '❌ Не удалось установить ${skill}, пропускаем'
    continue
  }
  
  # 3. Починить symlink для агента (если нужно)
  ssh root@${TARGET} "
    for agent_dir in ~/.openclaw/agents/*/agent/; do
      [ -d \"\$agent_dir\" ] && rm -rf \"\${agent_dir}skills\" && ln -sf ~/.openclaw/skills \"\${agent_dir}skills\"
    done
  "
  
  # 4. Проверить что агент видит скилл
  ssh root@${TARGET} "
    for agent_dir in ~/.openclaw/agents/*/agent/skills/; do
      [ -d \"\$agent_dir\" ] && ls \"\${agent_dir}${skill}/SKILL.md\" 2>/dev/null && echo '✅ Агент видит ${skill}' || echo '❌ Агент НЕ видит ${skill}'
    done
  "
  
  echo ''
done

# 5. Перезапустить
ssh root@${TARGET} "systemctl restart openclaw"

echo '✅ Установка завершена'
```

**Типичная проблема:** индивидуальные симлинки не обновляются при добавлении нового скилла. Надёжнее всегда удалять `skills/` и создавать symlink на всю глобальную директорию:
```bash
rm -rf ~/.openclaw/agents/main/agent/skills
ln -sf ~/.openclaw/skills ~/.openclaw/agents/main/agent/skills
```
После этого любые новые скиллы в `~/.openclaw/skills/` автоматически станут доступны агенту.

### Что НЕ делать

- ❌ Не копировать все скиллы пачкой без спроса
- ❌ Не использовать захардкоженный список — каталог динамический
- ❌ Не продолжать развёртывание пока пользователь не ответил

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
# Проверить КАЖДУЮ модель (стандарт: deepseek + glm)
for model in deepseek-v4-pro:cloud glm-5.1:cloud; do
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
- [ ] Память: memory/*.md, MEMORY.md, memory/contract.md (Memory Blueprint)
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
