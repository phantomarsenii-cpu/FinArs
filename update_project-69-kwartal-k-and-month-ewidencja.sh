#!/usr/bin/env bash
# Update 69:
#  1) Q1..Q4 -> K1..K4 (в приложении и во всех строках; в польском именно K),
#  2) в PDF "Ewidencja sprzedaży" — полное "Kwartał 3 2026 (lip-wrz)" вместо короткого,
#  3) при выборе периода для Ewidencja sprzedaży добавлен пункт "Ten miesiąc".
# Запускать из КОРНЯ репозитория.
set -euo pipefail

M=app/src/main
J=$M/java/com/example/fa_ksiegowy
for f in "$J/LimitsHelper.kt" "$J/ReportFragment.kt" "$J/EwidencjaPdfGenerator.kt"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

BK=".update69_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
for f in "$J/LimitsHelper.kt" "$J/ReportFragment.kt" "$J/EwidencjaPdfGenerator.kt" \
         "$M/res/values/strings.xml" "$M/res/values-pl/strings.xml" "$M/res/values-ru/strings.xml"; do
  cp "$f" "$BK/$(echo "$f" | tr '/' '_')"
done

python3 - <<'PY'
import re
M = "app/src/main"
J = M + "/java/com/example/fa_ksiegowy"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)

def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден фрагмент (" + what + ")"
    return s.replace(old, new)

# ---- 1) LimitsHelper: K вместо Q + параметр full для PDF ----
p = J + "/LimitsHelper.kt"
s = read(p)
if "full: Boolean" not in s:
    s = rep(s,
        "    fun quarterLabel(cal: Calendar): String {\n",
        "    fun quarterLabel(cal: Calendar, full: Boolean = false): String {\n", "quarterLabel signature")
    s = rep(s,
        '        return "Q$q ${cal.get(Calendar.YEAR)} ($months)"\n',
        '        // full = true -> pelne "Kwartał 3 2026 (lip-wrz)" (dokument PDF);\n'
        '        // full = false -> krotko "K3 2026 (lip-wrz)" (ekrany aplikacji).\n'
        '        val prefix = if (full) "Kwartał $q" else "K$q"\n'
        '        return "$prefix ${cal.get(Calendar.YEAR)} ($months)"\n', "quarterLabel return")
    s = re.sub(r"\bQ([1-4])\b", r"K\1", s)   # комментарии
    write(p, s)
else:
    print("LimitsHelper: уже применено")

# ---- 2) комментарий в PDF-генераторе ----
p = J + "/EwidencjaPdfGenerator.kt"
s = read(p)
n = re.sub(r"\bQ([1-4])\b", r"K\1", s).replace('"K3 2026 (lip-wrz)"', '"Kwartał 3 2026 (lip-wrz)"')
if n != s: write(p, n)

# ---- 3) ReportFragment: полный Kwartał в PDF + пункт "месяц" ----
p = J + "/ReportFragment.kt"
s = read(p)
if "generateEwidencjaForMonth" not in s:
    s = rep(s,
        "LimitsHelper.quarterLabel(now))\n",
        "LimitsHelper.quarterLabel(now, full = true))\n", "quarterLabel call")
    s = rep(s,
        '                "quarter" to getString(R.string.period_this_quarter),\n',
        '                "month" to getString(R.string.period_this_month),\n'
        '                "quarter" to getString(R.string.period_this_quarter),\n', "picker options")
    s = rep(s,
        '                "quarter" -> generateEwidencjaForQuarter()\n',
        '                "month" -> generateEwidencjaForMonth()\n'
        '                "quarter" -> generateEwidencjaForQuarter()\n', "picker when")
    s = rep(s,
        "    private fun generateEwidencjaForQuarter() {\n",
        "    /** Ewidencja za bieżący miesiąc kalendarzowy (od 1. dnia do teraz). */\n"
        "    private fun generateEwidencjaForMonth() {\n"
        "        val start = Calendar.getInstance().apply {\n"
        "            set(Calendar.DAY_OF_MONTH, 1)\n"
        "            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)\n"
        "        }\n"
        "        val endExclusive = (start.clone() as Calendar).apply { add(Calendar.MONTH, 1) }.timeInMillis\n"
        '        val label = SimpleDateFormat("LLLL yyyy", Locale("pl")).format(start.time)\n'
        "            .replaceFirstChar { it.uppercase() }\n"
        "        generateEwidencja(start.timeInMillis, minOf(System.currentTimeMillis(), endExclusive - 1), label)\n"
        "    }\n\n"
        "    private fun generateEwidencjaForQuarter() {\n", "quarter fun")
    s = s.replace("kwartał (domyślny, zgodny z limitem", "miesiąc, kwartał (domyślny, zgodny z limitem")
    write(p, s)
else:
    print("ReportFragment: уже применено")

# ---- 4) строки: Q1..Q4 -> K1..K4 (en / pl / ru; uk использует "I кв." — не Q) ----
for d in ("values", "values-pl", "values-ru"):
    p = M + "/res/" + d + "/strings.xml"
    s = read(p)
    n = re.sub(r"\bQ([1-4])\b", r"K\1", s)
    if n != s: write(p, n)
PY

echo "--- проверка ---"
if grep -rnE "\bQ[1-4]\b" $M/java $M/res --include=*.kt --include=*.xml; then
  echo "ОШИБКА: остались Q1..Q4"; exit 1
else
  echo "Q1..Q4 не осталось"
fi
python3 - <<'PY'
import re
for f in ("LimitsHelper.kt", "ReportFragment.kt"):
    s = open("app/src/main/java/com/example/fa_ksiegowy/" + f, encoding="utf-8").read()
    code = "\n".join(l.split("//")[0] for l in s.splitlines())
    ok = code.count("{") == code.count("}")
    print(f, "скобки { }:", code.count("{"), code.count("}"), "OK" if ok else "ОШИБКА")
    if not ok: raise SystemExit(1)
PY
echo "Готово. Бэкап: $BK"
