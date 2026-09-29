#!/usr/bin/env bash
# Update 71: фикс сборки обучающего тура (OnboardingTour.kt:181 — "Overload resolution ambiguity"
# на p.parent из-за smart-cast к View и ViewParent одновременно). Поиск ScrollView переписан
# без smart-cast. Запускать из КОРНЯ репозитория.
set -euo pipefail

F=app/src/main/java/com/example/fa_ksiegowy/OnboardingTour.kt
[ -f "$F" ] || { echo "Запусти из корня репозитория (нет $F)"; exit 1; }

python3 - <<'PY'
F = "app/src/main/java/com/example/fa_ksiegowy/OnboardingTour.kt"
s = open(F, encoding="utf-8").read()
old = """        var p = v.parent
        var sv: ScrollView? = null
        while (p is View) {
            if (p is ScrollView) { sv = p; break }
            p = p.parent
        }
"""
new = """        var cur: View? = v
        var sv: ScrollView? = null
        while (cur != null) {
            val par = cur.parent
            if (par is ScrollView) { sv = par; break }
            cur = par as? View
        }
"""
if old in s:
    open(F, "w", encoding="utf-8").write(s.replace(old, new))
    print("изменён:", F)
elif "var cur: View? = v" in s:
    print("уже применено")
else:
    raise SystemExit("не найден фрагмент в OnboardingTour.kt")
PY
