#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Update 41 fix 2: неверный import TextRecognizerOptions ==="
echo "Класс TextRecognizerOptions (латинский распознаватель) лежит в пакете"
echo "com.google.mlkit.vision.text.latin, а не в com.google.mlkit.vision.text — исправляю import."
echo ""

FILE="app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt"

if [ ! -f "settings.gradle" ] || [ ! -f "$FILE" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy (там, где settings.gradle)"
    exit 1
fi

if ! grep -q '^import com.google.mlkit.vision.text.TextRecognizerOptions$' "$FILE"; then
    echo "!!! Ожидаемая строка import не найдена — возможно, файл уже другой. Ничего не меняю."
    grep -n "^import com.google.mlkit" "$FILE"
    exit 1
fi

BACKUP_DIR=".update41_fix2_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/app/src/main/java/com/example/fa_ksiegowy"
cp "$FILE" "$BACKUP_DIR/$FILE"
echo "--- Бэкап сохранён в $BACKUP_DIR ---"

python3 - << 'PYEOF_U41FIX2'
path = "app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt"
text = open(path, encoding="utf-8").read()
old = "import com.google.mlkit.vision.text.TextRecognizerOptions\n"
new = "import com.google.mlkit.vision.text.latin.TextRecognizerOptions\n"
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX2
echo "OK: $FILE"

echo ""
grep -n "^import com.google.mlkit" "$FILE"
echo ""
echo "=== Готово. Дальше: ==="
echo "git add -A && git commit -m 'fix: correct TextRecognizerOptions import (latin package)' && git push"
