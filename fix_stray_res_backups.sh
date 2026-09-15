#!/data/data/com.termux/files/usr/bin/bash
# Naprawa buildu: usuniecie "osieroconych" plikow kopii zapasowych (*.bak_TIMESTAMP),
# ktore jakis wczesniejszy update-skrypt zostawil BEZPOSREDNIO w app/src/main/res/
# (zamiast w osobnym folderze .updateNN_backup_*). Android resource merger wymaga,
# zeby KAZDY plik w res/values i res/layout konczyl sie na .xml — stad blad builda:
#
#   ERROR: .../res/values-ru/strings.xml.bak_20260813_064748: file name must end with .xml
#   ERROR: .../res/layout/activity_mine.xml.bak_20260814_055605: file name must end with .xml
#   ERROR: .../res/values/strings.xml.bak_20260813_064748: file name must end with .xml
#   ERROR: .../res/values-pl/strings.xml.bak_20260813_064748: file name must end with .xml
#
# Te pliki to tylko stare kopie zapasowe (nie sa uzywane przez appke) — bezpiecznie
# je usunac, historia i tak jest w git. Skrypt szuka WSZYSTKICH plikow *.bak_* pod
# app/src/main/res (nie tylko tych 4 z errora), zeby na przyszlosc nie wyskoczyl
# ten sam blad z innym plikiem.
#
# Uruchamiac z korzenia repo, np.:
#   cd ~/FA_ksiegowy
#   bash fix_stray_res_backups.sh

set -e

if [ ! -d "app/src/main/res" ]; then
  echo "BLAD: nie widze app/src/main/res - uruchom skrypt z korzenia repo."
  exit 1
fi

echo "=== Szukam osieroconych plikow *.bak_* w app/src/main/res ==="
echo ""

FOUND=$(find app/src/main/res -type f -name "*.bak_*")

if [ -z "$FOUND" ]; then
  echo "Nic nie znaleziono — res/ jest czyste."
  exit 0
fi

echo "Znalezione pliki:"
echo "$FOUND"
echo ""

echo "$FOUND" | while IFS= read -r f; do
  git rm -q "$f" 2>/dev/null || rm -f "$f"
  echo "Usunieto: $f"
done

echo ""
echo "Gotowe."
echo ""
echo "Co zrobic dalej (Termux):"
echo "  git add -A"
echo "  git commit -m \"fix: usuniecie osieroconych plikow .bak_* z app/src/main/res (blokowaly merge resources)\""
echo "  git push origin main"
