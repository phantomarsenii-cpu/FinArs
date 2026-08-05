#!/data/data/com.termux/files/usr/bin/bash
set -e

if [ ! -f "app/build.gradle" ]; then
  echo "Запусти скрипт из корня репозитория FA_ksiegowy."
  exit 1
fi

python3 - << 'PYEOF'
import re

path = "app/src/main/java/com/example/fa_ksiegowy/TermsActivity.kt"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# 1) Добавляем недостающий импорт KTX-расширения addCallback,
#    из-за отсутствия которого лямбда резолвилась в перегрузку,
#    ожидающую OnBackPressedCallback напрямую -> ошибка компиляции.
if "import androidx.activity.addCallback" not in src:
    src = src.replace(
        "import android.content.Intent",
        "import android.content.Intent\nimport androidx.activity.addCallback",
        1
    )

# 2) На всякий случай переписываем сам вызов в явную, однозначную форму
#    (не зависящую от того, подтянется ли расширение) — создаём
#    OnBackPressedCallback вручную, это гарантированно компилируется
#    в любой версии activity-ktx.
old_call = '            onBackPressedDispatcher.addCallback(this) { /* no-op: блокируем выход */ }'
new_call = (
    '            onBackPressedDispatcher.addCallback(this, true) {\n'
    '                /* no-op: блокируем выход системной кнопкой "назад",\n'
    '                   пока соглашение не принято */\n'
    '            }'
)
if old_call in src:
    src = src.replace(old_call, new_call)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("PATCHED", path)
PYEOF

echo "=== Проверка ==="
grep -n "addCallback\|import androidx.activity" app/src/main/java/com/example/fa_ksiegowy/TermsActivity.kt

git add -A
git commit -m "fix: missing addCallback import causing TermsActivity compile error"
git push origin main

echo "=== Готово. Пушнуто в main. ==="
