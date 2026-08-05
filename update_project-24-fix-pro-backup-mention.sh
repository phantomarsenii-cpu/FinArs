#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 24: в описании Pro не было пункта 'Резервное копирование' ==="
echo "В приложении есть Pro-функция Backup/восстановление (Settings -> Backup (Pro)),"
echo "но она нигде не упоминалась в тексте о том, что даёт Pro — ни на экране Pro,"
echo "ни в диалоге 'Pro-версия'. Добавляем её везде, во всех 3 языках."
echo ""

# Меняем по имени строки (name="..."), не по старому тексту — так скрипт
# сработает независимо от того, применялось ли уже обновление 23.
replace_string_by_name() {
    local FILE="$1" NAME="$2" NEW_VALUE="$3"
    if [ ! -f "$FILE" ]; then
        echo "!!! Не найден $FILE"
        exit 1
    fi
    python3 - "$FILE" "$NAME" "$NEW_VALUE" << 'EOF_PY'
import sys, re, io

path, name, new_value = sys.argv[1], sys.argv[2], sys.argv[3]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(
    r'([ \t]*<string name="' + re.escape(name) + r'">).*?(</string>)',
    re.DOTALL
)
new_content, count = pattern.subn(lambda m: m.group(1) + new_value + m.group(2), content, count=1)

if count != 1:
    print("!!! Строка '%s' не найдена в %s" % (name, path))
    sys.exit(1)

with io.open(path, "w", encoding="utf-8") as f:
    f.write(new_content)

print("OK: %s -> %s обновлена" % (path, name))
EOF_PY
}

# --- English ---
replace_string_by_name \
    "app/src/main/res/values/strings.xml" \
    "pro_status_locked" \
    "Pro is locked. Unlock to get yearly/custom Excel reports, backup \\&amp; restore, and remove ads."

replace_string_by_name \
    "app/src/main/res/values/strings.xml" \
    "pro_info_message" \
    "Pro unlocks:\\n\\n• Yearly Excel report\\n• Custom-period Excel report\\n• Backup \\&amp; restore\\n• No ads\\n\\nThis is a one-time purchase — pay once, keep it forever."

# --- Russian ---
replace_string_by_name \
    "app/src/main/res/values-ru/strings.xml" \
    "pro_status_locked" \
    "Pro не активирован. Разблокируйте, чтобы получить годовые и произвольные отчёты в Excel, резервное копирование и восстановление, а также убрать рекламу."

replace_string_by_name \
    "app/src/main/res/values-ru/strings.xml" \
    "pro_info_message" \
    "Pro открывает:\\n\\n• Годовой отчёт в Excel\\n• Отчёт за произвольный период\\n• Резервное копирование и восстановление\\n• Без рекламы\\n\\nЭто разовая покупка — платите один раз, доступ остаётся навсегда."

# --- Polish ---
replace_string_by_name \
    "app/src/main/res/values-pl/strings.xml" \
    "pro_status_locked" \
    "Pro jest zablokowane. Odblokuj, aby uzyskać roczne i niestandardowe raporty Excel, kopię zapasową i przywracanie danych oraz usunąć reklamy."

replace_string_by_name \
    "app/src/main/res/values-pl/strings.xml" \
    "pro_info_message" \
    "Pro odblokowuje:\\n\\n• Raport roczny w Excelu\\n• Raport za dowolny okres\\n• Kopia zapasowa i przywracanie danych\\n• Brak reklam\\n\\nTo jednorazowy zakup — płacisz raz, dostęp zostaje na zawsze."

echo ""
echo "=== Готово. Пересобери APK: ./gradlew assembleDebug ==="
echo "=== git add -A && git commit -m 'Fix: mention Backup/restore as a Pro feature everywhere' && git push ==="
echo ""
echo "!!! ВАЖНО перед тестом рекламы и текстов:"
echo "1) Полностью удали старую версию FinArs с телефона (не просто обнови поверх)"
echo "   — иначе можно случайно тестировать старый APK."
echo "2) Установи заново APK из app/build/outputs/apk/debug/app-debug.apk"
echo "3) Только после этого делай новые скриншоты — старые скриншоты с тем же"
echo "   краш-сообщением 'adSize was missing' означают, что тестировался старый билд."
