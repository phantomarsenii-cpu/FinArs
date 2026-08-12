#!/data/data/com.termux/files/usr/bin/bash
# Update 61: FIX — update 59 сбросил versionCode с огромного числа (минуты
# с 2025-01-01, на сегодня ~847000+) обратно на маленький счётчик (1, 2, 3...).
# Android считает это ПОНИЖЕНИЕМ версии и отказывается устанавливать/обновлять
# APK ("Приложение не установлено") на любом телефоне, где уже стоит версия
# со старой (большой) схемой versionCode.
#
# Фикс: поднимаем стартовое значение version.txt до безопасной базы (900000),
# которая гарантированно выше любого versionCode, который вообще мог быть
# сгенерирован старой схемой (максимум на сегодня — около 847524). Дальше
# счётчик как и раньше растёт на 1 с каждым билдом (900001, 900002, ...) —
# логика в build.gradle НЕ меняется, меняется только текущее значение
# version.txt.
#
# Запускать из корня репо (там где app/ и .git/):
#   cd ~/FA_ksiegowy
#   bash update_project-61-fix-versioncode-downgrade.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update61_backup_${TS}"

SAFE_BASELINE=900000

echo "=== Update 61: fix versionCode downgrade (version.txt -> $SAFE_BASELINE) ==="
echo ""

if [ ! -f "version.txt" ] || [ ! -f "app/build.gradle" ]; then
  echo "BLAD: nie widze version.txt lub app/build.gradle - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp "version.txt" "$BACKUP_DIR/version.txt"
echo "--- Backup version.txt zapisany w $BACKUP_DIR ---"

CURRENT=$(cat version.txt | tr -d '[:space:]')

if ! [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
  echo "BLAD: version.txt zawiera nie-liczbowa wartosc: '$CURRENT'"
  exit 1
fi

if [ "$CURRENT" -ge "$SAFE_BASELINE" ]; then
  echo "Pominieto: version.txt ($CURRENT) juz jest >= $SAFE_BASELINE, nie trzeba nic zmieniac."
else
  echo "$SAFE_BASELINE" > version.txt
  echo "OK: version.txt: $CURRENT -> $SAFE_BASELINE"
  echo "Nastepny build bedzie mial versionCode $((SAFE_BASELINE + 1)) — to bezpiecznie"
  echo "wiecej niz jakikolwiek versionCode ze starej schemy (max ~847524 na dzis)."
fi

echo ""
echo "Gotowe."
echo ""
echo "WAZNE: to NIE naprawi telefonu, na ktorym juz stoi apka ze starym, wielkim"
echo "versionCode z bledem instalacji — jesli po tym update nadal 'Aplikacja nie"
echo "zainstalowana', odinstaluj FA/FinArs recznie przez:"
echo "  Ustawienia -> Aplikacje -> FinArs -> Odinstaluj"
echo "(a NIE tylko usuniecie pliku .apk z Pobranych — to nie to samo)."
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 61: fix versionCode downgrade after update 59\""
echo "  git push origin main"
