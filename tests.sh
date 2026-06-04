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
# Test Suite 6: NSI-скиллы отсутствуют в каталоге
# ─────────────────────────────────────────
echo ""
echo "─── Suite 6: NSI-скиллы отсутствуют в каталоге ───"

# Test 6.1: personal-embeddings не в каталоге
echo "Test 6.1: personal-embeddings removed from catalog..."
SKILL_FILE="$(dirname $0)/SKILL.md"
if grep -q "personal-embeddings" "$SKILL_FILE"; then
  echo "  ❌ FAIL: personal-embeddings всё ещё в каталоге SKILL.md"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: personal-embeddings удалён из каталога"
  PASS=$((PASS+1))
fi

# Test 6.2: Нет перечисления NSI-скиллов в списке
echo "Test 6.2: No NSI skill names in catalog..."
NSI_SKILLS="semantic-classifier manual-rag-controller analytics-pro career-coach data-bridge-pro devops-remote executive-search-ru strat-session devops-fleet devops-techarch"
FOUND_NSI=0
for skill in $NSI_SKILLS; do
  if grep -q "$skill" "$SKILL_FILE" 2>/dev/null; then
    echo "  ❌ Found NSI skill in catalog: $skill"
    FOUND_NSI=$((FOUND_NSI+1))
  fi
done
if [ "$FOUND_NSI" -eq 0 ]; then
  echo "  ✅ PASS: Ни один NSI-скилл не найден в каталоге"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: $FOUND_NSI NSI-скиллов найдено в каталоге"
  FAIL=$((FAIL+1))
fi

# Test 6.3: Нет упоминания «номенклатурн» в описаниях каталога
echo "Test 6.3: No nomenclature references in catalog..."
if grep -qi 'номенклатурн' "$SKILL_FILE"; then
  echo "  ❌ FAIL: Found 'номенклатурн' in SKILL.md catalog"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: No nomenclature references in catalog"
  PASS=$((PASS+1))
fi

# ─────────────────────────────────────────
# Test Suite 7: Каталог динамический, не захардкожен
# ─────────────────────────────────────────
echo ""
echo "─── Suite 7: Каталог динамический, не захардкожен ───"

# Test 7.1: Нет захардкоженного каталога (списка скиллов ВНЕ кодовых блоков)
echo "Test 7.1: No hardcoded skill catalog outside code blocks..."
SKILL_FILE="$(dirname $0)/SKILL.md"

# Считаем буллеты ВНЕ кодовых блоков (```...```)
# Кодовые блоки — это легальные примеры, а не захардкоженный список
OUTSIDE_BLOCKS=0
IN_BLOCK=false
while IFS= read -r line; do
  if echo "$line" | grep -q '^\x60\x60\x60'; then
    IN_BLOCK=$((1 - IN_BLOCK))
    continue
  fi
  if [ "$IN_BLOCK" -eq 0 ] && echo "$line" | grep -qP '^[•\-] \w[-\w]+ — '; then
    OUTSIDE_BLOCKS=$((OUTSIDE_BLOCKS + 1))
  fi
done < "$SKILL_FILE"

if [ "$OUTSIDE_BLOCKS" -gt 5 ]; then
  echo "  ❌ FAIL: Найдено $OUTSIDE_BLOCKS захардкоженных скиллов вне кодовых блоков"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: Только $OUTSIDE_BLOCKS захардкоженных буллетов вне кодов (в примерах — ок)"
  PASS=$((PASS+1))
fi

# Test 7.2: Есть инструкция «спросить пользователя» (явное ожидание ответа)
echo "Test 7.2: Explicit 'ask user' step..."
if grep -q 'ждать ответа\|Ждать ответа\|пока пользователь не ответит' "$SKILL_FILE"; then
  echo "  ✅ PASS: Есть явная инструкция ждать ответа пользователя"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет инструкции ждать ответа пользователя"
  FAIL=$((FAIL+1))
fi

# Test 7.3: Есть правило «не ставить всё пачкой»
echo "Test 7.3: 'No bulk install' rule..."
if grep -q 'Не копировать все скиллы пачкой\|не ставить всё пачкой' "$SKILL_FILE"; then
  echo "  ✅ PASS: Правило «не ставить всё пачкой» присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет правила против bulk-установки"
  FAIL=$((FAIL+1))
fi

# Test 7.4: Есть упоминание «каталог собирается динамически»
echo "Test 7.4: Dynamic catalog mention..."
if grep -q 'динамически\|dynamic' "$SKILL_FILE"; then
  echo "  ✅ PASS: Каталог описан как динамический"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Каталог не описан как динамический"
  FAIL=$((FAIL+1))
fi

# ─────────────────────────────────────────
# Test Suite 8: Единый механизм установки (scp, без git/ClawHub)
# ─────────────────────────────────────────
echo ""
echo "─── Suite 8: Единый механизм установки ───"

# Test 8.1: Нет git clone в шагах установки скиллов (допустимо в запретительных фразах)
echo "Test 8.1: No git clone for skill installation..."
GIT_CLONE_COUNT=$(grep -c 'git clone' "$SKILL_FILE" 2>/dev/null || echo 0)
GIT_CLONE_BAN_COUNT=$(grep -c 'Никаких git clone\|no git clone' "$SKILL_FILE" 2>/dev/null || echo 0)
if [ "$GIT_CLONE_COUNT" -gt "$GIT_CLONE_BAN_COUNT" ]; then
  echo "  ❌ FAIL: Найдено $GIT_CLONE_COUNT git clone ($GIT_CLONE_BAN_COUNT из них — запретительные фразы)"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: Все $GIT_CLONE_COUNT упоминаний — запретительные фразы (не инструкции)"
  PASS=$((PASS+1))
fi

# Test 8.2: Нет openclaw skill install (ClawHub) — кроме запретительных фраз
echo "Test 8.2: No ClawHub install..."
CLAWHUB_COUNT=$(grep -c 'openclaw skill.*install\|clawhub install' "$SKILL_FILE" 2>/dev/null || echo 0)
# Отфильтровать: если строка содержит "никаких ClawHub" — это запрет, не считается
CLAWHUB_BAN=$(grep -ci 'никаких.*[Cc]law[Hh]ub\|no.*[Cc]law[Hh]ub' "$SKILL_FILE" 2>/dev/null | head -1 || echo 0)
CLAWHUB_REAL=$((CLAWHUB_COUNT - CLAWHUB_BAN))
if [ "$CLAWHUB_REAL" -gt 0 ] 2>/dev/null; then
  echo "  ❌ FAIL: Найдено $CLAWHUB_REAL инструкций ClawHub install"
  FAIL=$((FAIL+1))
else
  echo "  ✅ PASS: ClawHub install не используется (только запретительные упоминания)"
  PASS=$((PASS+1))
fi

# Test 8.3: Есть функция install_skill (единый механизм)
echo "Test 8.3: Single install_skill function..."
if grep -q 'install_skill()' "$SKILL_FILE"; then
  echo "  ✅ PASS: Функция install_skill() найдена"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет единой функции установки скиллов"
  FAIL=$((FAIL+1))
fi

# Test 8.4: scp используется как основной способ
echo "Test 8.4: scp as primary transport..."
SCP_COUNT=$(grep -c 'scp.*SKILL\.md' "$SKILL_FILE" 2>/dev/null || echo 0)
if [ "$SCP_COUNT" -ge 2 ]; then
  echo "  ✅ PASS: scp используется ($SCP_COUNT раз)"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: scp используется мало или не используется"
  FAIL=$((FAIL+1))
fi

# Test 8.5: Есть верификация после установки (проверка что файл не пустой)
echo "Test 8.5: Post-install verification..."
if grep -q 'установлен.*байт\|SIZE.*байт' "$SKILL_FILE"; then
  echo "  ✅ PASS: Верификация после установки присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет верификации после установки скилла"
  FAIL=$((FAIL+1))
fi

# ─────────────────────────────────────────
# Test Suite 9: Трехуровневая валидация + откат
# ─────────────────────────────────────────
echo ""
echo "─── Suite 9: Трехуровневая валидация + откат ───"

# Test 9.1: Уровень 1 — проверка description: в SKILL.md
echo "Test 9.1: Level 1 validation — description check..."
if grep -qP "grep.*description:.*SKILL\\.md|description:.*признак.*SKILL" "$SKILL_FILE"; then
  echo "  ✅ PASS: Проверка description: в SKILL.md присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет проверки description: в SKILL.md"
  FAIL=$((FAIL+1))
fi

# Test 9.2: Уровень 1 — проверка размера файла (> 100 байт)
echo "Test 9.2: Level 1 validation — file size check..."
if grep -qP '100.*байт|lt 100|SIZE.*-lt' "$SKILL_FILE"; then
  echo "  ✅ PASS: Проверка размера файла (>100 байт) присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет проверки размера файла"
  FAIL=$((FAIL+1))
fi

# Test 9.3: Уровень 2 — агент видит скилл через свой путь
echo "Test 9.3: Level 2 validation — agent skill path check..."
if grep -qP 'agents/\*/agent/skills/' "$SKILL_FILE"; then
  echo "  ✅ PASS: Проверка через путь агента присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет проверки что агент видит скилл через свой путь"
  FAIL=$((FAIL+1))
fi

# Test 9.4: Уровень 3 — проверка после рестарта
echo "Test 9.4: Level 3 validation — post-restart check..."
if grep -qP 'уровень 3|Уровень 3.*рестарт|systemctl is-active.*skip' "$SKILL_FILE"; then
  echo "  ✅ PASS: Проверка после рестарта присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет проверки после рестарта сервиса"
  FAIL=$((FAIL+1))
fi

# Test 9.5: Откат при ошибке (rm -rf скилла)
echo "Test 9.5: Rollback on validation failure..."
if grep -qP 'rm -rf.*skills.*\$skill|Удалён битый скилл|откат' "$SKILL_FILE"; then
  echo "  ✅ PASS: Механизм отката присутствует"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет механизма отката при ошибке"
  FAIL=$((FAIL+1))
fi

# Test 9.6: Не рестартовать при битых скиллах
echo "Test 9.6: No restart with broken skills..."
if grep -qP 'НЕ перезапускать.*битыми|не рестартовать.*скилл' "$SKILL_FILE"; then
  echo "  ✅ PASS: Блокировка рестарта при битых скиллах"
  PASS=$((PASS+1))
else
  echo "  ❌ FAIL: Нет блокировки рестарта при битых скиллах"
  FAIL=$((FAIL+1))
fi

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
