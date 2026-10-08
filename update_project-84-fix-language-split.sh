#!/usr/bin/env bash
# Update 84: фикс переключения языка в приложении (выбираешь украинский — ставится английский).
# Причина: релиз собирается как AAB для Google Play, а Play по умолчанию доставляет на устройство
# только языки, выбранные в системе телефона (language split). Остальные (напр. uk) не приходят,
# и Android откатывается на английский. Отключаем разделение по языкам — все 4 языка всегда в установке.
# Запускать из КОРНЯ репозитория, ДО git add/commit/push. Скрипт идемпотентный.
set -euo pipefail
F=app/build.gradle
[ -f "$F" ] || { echo "Запусти из корня репозитория (нет $F)"; exit 1; }
B=".update84_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$B/app"
cp "$F" "$B/app/"
python3 - <<'PY'
p = "app/build.gradle"
s = open(p, encoding="utf-8").read()
if "enableSplit = false" in s:
    print("build.gradle: уже применено")
else:
    old = "    kotlinOptions { jvmTarget = '17' }\n"
    assert s.count(old) == 1, "не найден kotlinOptions в build.gradle"
    new = old + (
        "\n"
        "    // Update 84: не делить AAB по языкам — иначе Google Play не доставляет языки, которых нет\n"
        "    // в системных настройках телефона, и ручной выбор языка в приложении откатывается на английский.\n"
        "    bundle {\n"
        "        language {\n"
        "            enableSplit = false\n"
        "        }\n"
        "    }\n")
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
    print("build.gradle: добавлен bundle { language { enableSplit = false } }")
PY
echo "Готово. Бэкап: $B"
