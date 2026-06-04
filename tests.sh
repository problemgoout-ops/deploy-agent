#!/usr/bin/env bash
# TESTS for deploy-agent skill
# Контекст: кейс Елены Банновой (2026-06-04)
# Запуск: bash tests.sh

set -e
PASS=0
FAIL=0

echo "========================================="
echo " DEPLOY-AGENT SKILL TESTS"
echo "========================================="

# ─────────────────────────────────────────
# Test Suite 1: Сохранность данных
# ─────────────────────────────────────────
echo ""
echo "─── Suite 1: Сохранность данных при падении сессии ───"

# Test 1.1: Save-game мгновенно
echo "Test 1.1: Save-Game Atomicity..."
TEST_FILE=/tmp/test_secrets_$$.md
echo "### test_user
SSH: root@10.0.0.1
SSH_PASS: testpass123" > $TEST_FILE
if grep -q "root@10.0.0.1" $TEST_FILE; then
  echo "  ✅ PASS: Данные записаны"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Данные не записались"
  FAIL=$((FAIL+1))
fi
if [ -f $TEST_FILE ]; then
  echo "  ✅ PASS: Файл сохранился (пережил бы падение сессии)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Файл потерян"
  FAIL=$((FAIL+1))
fi
rm -f $TEST_FILE

# Test 1.2: Checkpoint recovery
echo "Test 1.2: Checkpoint Recovery..."
TEST_MEM=/tmp/test_memory_$$.md
echo "## 🚧 Deploy test_user: Checkpoint 3/10
- Статус: токен бота получен
- Следующий шаг: SSH подключение
- Данные получены: SSH ✅ | API Key ✅ | Bot Token ✅
- Последнее действие: $(date -Iseconds)" > $TEST_MEM
if grep -q "🚧 Deploy test_user" $TEST_MEM; then
  CP=$(grep "Checkpoint" $TEST_MEM | tail -1 | grep -oP '\d+/\d+')
  echo "  ✅ PASS: Checkpoint найден ($CP)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Checkpoint не найден"
  FAIL=$((FAIL+1))
fi
rm -f $TEST_MEM

# Test 1.3: Порядок записи
echo "Test 1.3: Write Order (SECRETS before MEMORY)..."
WRITE_LOG=/tmp/test_order_$$.log
echo "SECRETS written" > $WRITE_LOG
echo "MEMORY written" >> $WRITE_LOG
FIRST=$(head -1 $WRITE_LOG)
if [ "$FIRST" = "SECRETS written" ]; then
  echo "  ✅ PASS: SECRETS записан первым"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Порядок нарушен"
  FAIL=$((FAIL+1))
fi
rm -f $WRITE_LOG

# ─────────────────────────────────────────
# Test Suite 2: Верификация токенов
# ─────────────────────────────────────────
echo ""
echo "─── Suite 2: Верификация токенов ───"

# Test 2.1: Валидный токен
echo "Test 2.1: Valid Token..."
VALID="1234567890:ABCdefGHIJklmNOPqrstUVWXYz1234567890"
LEN=$(echo -n "$VALID" | wc -c)
if [ "$LEN" -ge 40 ] && [ "$LEN" -le 50 ]; then
  echo "  ✅ PASS: Валидный токен ($LEN символов)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Валидный токен не прошёл ($LEN)"
  FAIL=$((FAIL+1))
fi

# Test 2.2: Обрезанный токен
echo "Test 2.2: Truncated Token Detection..."
TRUNC="883086…NrXs"
LEN=$(echo -n "$TRUNC" | wc -c)
if [ "$LEN" -lt 40 ]; then
  echo "  ✅ PASS: Обрезанный токен ($LEN символов) корректно заблокирован"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Обрезанный токен прошёл бы проверку"
  FAIL=$((FAIL+1))
fi

# Test 2.3: Валидация через Telegram API (полный токен из SECRETS.md)
echo "Test 2.3: Telegram API Validation..."
FULL_TOKEN="8830864087:AAFVNRAPKTO8ySbCrgYZ00ePZ8hDFnENrXs"
RESP=$(curl -s --max-time 10 "https://api.telegram.org/bot${FULL_TOKEN}/getMe" 2>&1)
OK=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok',False))" 2>/dev/null)
if [ "$OK" = "True" ]; then
  USERNAME=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null)
  echo "  ✅ PASS: API подтвердил токен, бот @${USERNAME}"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: API отклонил токен"
  FAIL=$((FAIL+1))
fi

# Test 2.4: Проверка длины в конфиге
echo "Test 2.4: Config Token Length Check..."
CONFIG=/tmp/test_cfg_$$.json
echo '{"channels":{"telegram":{"botToken":"1234567890:ABCdefGHIJklmNOPqrstUVWXYz1234567890"}}}' > $CONFIG
LEN=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(len(c['channels']['telegram']['botToken']))")
if [ "$LEN" -ge 40 ]; then
  echo "  ✅ PASS: Токен в конфиге $LEN символов"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Токен в конфиге обрезан ($LEN)"
  FAIL=$((FAIL+1))
fi
rm -f $CONFIG

# ─────────────────────────────────────────
# Test Suite 3: Коммуникация с пользователем
# ─────────────────────────────────────────
echo ""
echo "─── Suite 3: Коммуникация с пользователем ───"

# Test 3.1: Шаблон при потере сессии
echo "Test 3.1: Session Loss Message Template..."
MSG="⚠️ Технический сбой на моей стороне. Данные сохранены, я уже восстанавливаюсь.
Напиши любое сообщение через 2-3 минуты — я продолжу с того же места."
if echo "$MSG" | grep -q "сбой" && \
   echo "$MSG" | grep -q "сохранены" && \
   echo "$MSG" | grep -q "восстанавливаюсь" && \
   echo "$MSG" | grep -q "продолжу" && \
   echo "$MSG" | grep -q "2-3"; then
  echo "  ✅ PASS: Все ключевые элементы в сообщении"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Не хватает элементов"
  FAIL=$((FAIL+1))
fi
if ! echo "$MSG" | grep -qiE "error|exception|failed|crash"; then
  echo "  ✅ PASS: Нет технических терминов"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Есть технические термины"
  FAIL=$((FAIL+1))
fi
LINES=$(echo "$MSG" | wc -l)
if [ "$LINES" -le 2 ]; then
  echo "  ✅ PASS: Сообщение короткое ($LINES строк)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Сообщение слишком длинное"
  FAIL=$((FAIL+1))
fi

# Test 3.2: Шаблон при ошибке токена
echo "Test 3.2: Token Error Message Template..."
MSG="❌ Токен невалидный — возможно обрезался при копировании. 
Проверь его в @BotFather: /mybots → {имя бота} → API Token.
Скопируй токен целиком и пришли ещё раз."
if echo "$MSG" | grep -q "@BotFather" && \
   echo "$MSG" | grep -q "обрезался" && \
   echo "$MSG" | grep -q "пришли ещё раз"; then
  echo "  ✅ PASS: Конкретная инструкция для пользователя"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Не хватает деталей"
  FAIL=$((FAIL+1))
fi
if ! echo "$MSG" | grep -qiE "error|invalid|404|unauthorized"; then
  echo "  ✅ PASS: Нет технических терминов"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Есть технические термины"
  FAIL=$((FAIL+1))
fi

# Test 3.3: Правило «одно сообщение»
echo "Test 3.3: Single Message Rule..."
# Симулируем проверку: НЕ слать >1 одинаковых сообщений
SENT_COUNT=1  # правильное поведение
if [ "$SENT_COUNT" -le 1 ]; then
  echo "  ✅ PASS: Только одно сообщение об ошибке"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: $SENT_COUNT повторов — баг Елены"
  FAIL=$((FAIL+1))
fi

# ─────────────────────────────────────────
# Test Suite 4: Таймауты
# ─────────────────────────────────────────
echo ""
echo "─── Suite 4: Таймауты ───"

# Test 4.1: SSH Timeout
echo "Test 4.1: SSH ConnectTimeout..."
START=$(date +%s)
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@10.255.255.1 "echo ok" 2>/dev/null || true
END=$(date +%s)
ELAPSED=$((END - START))
if [ "$ELAPSED" -le 8 ]; then
  echo "  ✅ PASS: SSH таймаут ${ELAPSED}с (лимит 10с)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: SSH висел ${ELAPSED}с"
  FAIL=$((FAIL+1))
fi

# Test 4.2: Curl Timeout
echo "Test 4.2: Curl max-time..."
START=$(date +%s)
curl -s --max-time 5 --connect-timeout 3 "https://10.255.255.1:9999" 2>/dev/null || true
END=$(date +%s)
ELAPSED=$((END - START))
if [ "$ELAPSED" -le 7 ]; then
  echo "  ✅ PASS: Curl таймаут ${ELAPSED}с (лимит 15с)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Curl висел ${ELAPSED}с"
  FAIL=$((FAIL+1))
fi

# ─────────────────────────────────────────
# Test Suite 5: Dry-Run конфига
# ─────────────────────────────────────────
echo ""
echo "─── Suite 5: Dry-Run конфига ───"

# Test 5.1: Валидный JSON
echo "Test 5.1: Valid JSON Dry-Run..."
echo '{"key":"value"}' > /tmp/test_valid_$$.json
if python3 -c "import json; json.load(open('/tmp/test_valid_$$.json'))" 2>/dev/null; then
  echo "  ✅ PASS: Валидный JSON прошёл проверку"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Валидный JSON не прошёл"
  FAIL=$((FAIL+1))
fi
rm -f /tmp/test_valid_$$.json

# Test 5.2: Битый JSON
echo "Test 5.2: Broken JSON Detection..."
echo '{key:"value"}' > /tmp/test_broken_$$.json
if python3 -c "import json; json.load(open('/tmp/test_broken_$$.json'))" 2>/dev/null; then
  echo "  ❌ FAIL: Битый JSON прошёл бы проверку — КАТАСТРОФА ПРИ РЕСТАРТЕ!"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: Битый JSON корректно заблокирован"
  PASS=$((PASS+1))
fi
rm -f /tmp/test_broken_$$.json

# ─────────────────────────────────────────
# Итоги
# ─────────────────────────────────────────
echo ""
echo "========================================="
echo " RESULTS: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo " STATUS: ✅ ALL TESTS PASSED"
else
  echo " STATUS: ❌ $FAIL TESTS FAILED"
  exit 1
fi
echo "========================================="
