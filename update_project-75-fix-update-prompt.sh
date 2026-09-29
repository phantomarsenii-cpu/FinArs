#!/usr/bin/env bash
# Update 75: фикс сборки UpdatePrompt.kt (Val cannot be reassigned / Type mismatch, строки 119 и 133):
# локальная переменная `text` затеняла свойство TextView.text внутри apply { text = ... }.
# Переменная переименована в bodyView. Запускать из КОРНЯ репозитория.
set -euo pipefail

F=app/src/main/java/com/example/fa_ksiegowy/UpdatePrompt.kt
[ -f "$F" ] || { echo "Запусти из корня репозитория (нет $F)"; exit 1; }

python3 - <<'PY'
F = "app/src/main/java/com/example/fa_ksiegowy/UpdatePrompt.kt"
s = open(F, encoding="utf-8").read()
if "val bodyView = TextView(activity)" in s:
    print("уже применено")
else:
    a = "        val text = TextView(activity).apply {\n"
    b = "        c.addView(text)\n"
    assert s.count(a) == 1 and s.count(b) == 1, "не найден фрагмент в UpdatePrompt.kt"
    s = s.replace(a, "        val bodyView = TextView(activity).apply {\n").replace(b, "        c.addView(bodyView)\n")
    open(F, "w", encoding="utf-8").write(s)
    print("изменён:", F)
PY
