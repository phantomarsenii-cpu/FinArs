#!/usr/bin/env bash
# Update 78: фикс зависаний на телефонах со старым Android (Note 10+, Android 12 и ниже).
# Причина: с добавлением языков (#218/#219) LocaleHelper вызывает AppCompatDelegate.setApplicationLocales()
# при КАЖДОМ старте процесса (FaApp.onCreate) и при смене языка. На Android 13+ (Samsung S23) это
# делает системный LocaleManager — безопасно. На Android 12 и ниже AppCompat включает СВОЙ обходной
# механизм, который конфликтует с нашей обёрткой языка в BaseActivity.attachBaseContext
# (createConfigurationContext) — Activity начинают пересоздаваться/дёргаться, касания пропадают.
# Наш собственный механизм языка (attachBaseContext + перезапуск MainActivity после выбора языка в
# SettingsLanguageActivity) для старых Android уже полностью достаточен, поэтому на API < 33
# вызовы AppCompatDelegate.setApplicationLocales() отключены. На Android 13+ поведение не меняется.
# Запускать из КОРНЯ репозитория.
set -euo pipefail

F=app/src/main/java/com/example/fa_ksiegowy/LocaleHelper.kt
[ -f "$F" ] || { echo "Запусти из корня репозитория (нет $F)"; exit 1; }

python3 - <<'PY'
F = "app/src/main/java/com/example/fa_ksiegowy/LocaleHelper.kt"
s = open(F, encoding="utf-8").read()
if "Update 78" in s:
    print("уже применено")
    raise SystemExit(0)

call1 = "        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(code))\n"
call2 = "        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(getOrInitLanguage(context)))\n"
assert s.count(call1) == 1 and s.count(call2) == 1, "не найдены вызовы setApplicationLocales"

note = ("        // Update 78: на Android 12 и ниже (API < 33) AppCompat использует свой обходной механизм,\n"
        "        // который конфликтует с attachBaseContext-обёрткой и вызывает лаги/пересоздание Activity.\n"
        "        // Там язык применяют attachBaseContext + перезапуск MainActivity, поэтому вызов пропускаем.\n")
s = s.replace(call1, note + "        if (android.os.Build.VERSION.SDK_INT >= 33) {\n    " + call1 + "        }\n")
s = s.replace(call2, note + "        if (android.os.Build.VERSION.SDK_INT >= 33) {\n    " + call2 + "        }\n")
open(F, "w", encoding="utf-8").write(s)
print("изменён:", F)
PY
