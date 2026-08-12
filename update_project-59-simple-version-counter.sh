#!/data/data/com.termux/files/usr/bin/bash
# Update 59: numer wersji (widoczny w Ustawieniach telefonu) byl oparty o
# date/godzine builda (np. "1.2026.08.12"). Teraz to zwykly rosnacy licznik:
# 1.0, 1.1, 1.2, 1.3, ... Licznik trzymany jest w pliku version.txt w
# korzeniu repo. GitHub Actions po KAZDYM udanym buildzie automatycznie
# zwieksza go o 1 i commituje z powrotem do repo — dzieki temu kolejny build
# dostaje kolejny numer bez zadnej recznej pracy.
#
# UWAGA: ten skrypt zastepuje wczesniejszy pomysl z data/godzina w nazwie
# wersji — jesli pobrales wczesniej "update_project-59-version-name-time.sh",
# NIE uruchamiaj go, uzyj tylko tego skryptu.
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-59-simple-version-counter.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update59_backup_${TS}"

echo "=== Update 59: numer wersji jako prosty licznik (1.0, 1.1, 1.2, ...) ==="
echo "Co sie zmienia:"
echo "  1) Nowy plik version.txt w korzeniu repo (start: 0 -> pierwszy build to 1.0)."
echo "  2) app/build.gradle czyta ten plik zamiast liczyc date/godzine builda."
echo "  3) .github/workflows/build.yml: po kazdym udanym buildzie licznik jest"
echo "     zwiekszany o 1 i commitowany z powrotem do repo (krok 'Bump build"
echo "     version number'), zeby nastepny build mial kolejny numer."
echo ""

if [ ! -f "app/build.gradle" ] || [ ! -f ".github/workflows/build.yml" ]; then
  echo "BLAD: nie widze app/build.gradle lub .github/workflows/build.yml - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR/app"
mkdir -p "$BACKUP_DIR/.github/workflows"
cp "app/build.gradle" "$BACKUP_DIR/app/build.gradle"
cp ".github/workflows/build.yml" "$BACKUP_DIR/.github/workflows/build.yml"
if [ -f "version.txt" ]; then
    cp "version.txt" "$BACKUP_DIR/version.txt"
fi
echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

# ---------------------------------------------------------------------------
# 1) version.txt — tworzymy tylko jesli jeszcze nie istnieje (zeby powtorne
#    uruchomienie skryptu nie zresetowalo licznika do zera).
# ---------------------------------------------------------------------------
if [ -f "version.txt" ]; then
    echo "Pominieto: version.txt juz istnieje (zawartosc: $(cat version.txt)), nie nadpisuje."
else
    echo "0" > version.txt
    echo "OK: utworzono version.txt (start: 0 -> pierwszy build bedzie mial numer 1.0)"
fi

python3 << 'PYEOF'
import sys

def str_replace(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        print(f"BLAD ({count} wystapien zamiast 1): {label} w {path}")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {label} -> {path}")

# ---------------------------------------------------------------------------
# 2) app/build.gradle — licznik z version.txt zamiast daty/godziny
# ---------------------------------------------------------------------------
GRADLE = "app/build.gradle"

str_replace(
    GRADLE,
    """// Update: wersja aplikacji byla zahardkodowana (versionCode 1 / "1.0") i nigdy
// sie nie zmieniala, wiec Android nie widzial nowej wersji przy kazdej
// instalacji. Liczymy versionCode automatycznie z aktualnego czasu (minuty od
// wlasnego "zerowego" punktu w czasie, zeby liczba zmiescila sie w Int i byla
// mala) — kazdy build ma wiec zawsze wiekszy, unikalny kod. versionName
// pokazuje czytelna date builda.
def CUSTOM_EPOCH_MILLIS = 1735689600000L // 2025-01-01 00:00:00 UTC
def autoVersionCode = (int) ((System.currentTimeMillis() - CUSTOM_EPOCH_MILLIS) / 60000L)
def buildDateStamp = new Date().format('yyyy.MM.dd')""",
    """// Update: numer wersji byl oparty o date/godzine builda (nieczytelny, nie
// rosnie w prosty sposob). Teraz numer wersji to zwykly licznik zapisany w
// pliku version.txt w korzeniu repo: 1.0, 1.1, 1.2, ... Plik jest odczytywany
// tutaj (versionCode/versionName), a incrementowany i commitowany z powrotem
// do repo automatycznie przez GitHub Actions PO kazdym udanym buildzie (patrz
// .github/workflows/build.yml, krok "Bump build version number") — dzieki
// czemu kolejny build automatycznie dostaje kolejny numer, bez recznej pracy.
def versionFile = file("$rootDir/version.txt")
def buildNumber = versionFile.exists() ? versionFile.text.trim().toInteger() : 0
def buildDateStamp = "${buildNumber}\"""",
    "licznik wersji z version.txt",
)

str_replace(
    GRADLE,
    """        versionCode autoVersionCode
        versionName "1.${buildDateStamp}\"""",
    """        versionCode buildNumber + 1
        versionName "1.${buildDateStamp}\"""",
    "versionCode/versionName z licznika",
)

# ---------------------------------------------------------------------------
# 3) .github/workflows/build.yml — uprawnienia do zapisu + krok zwiekszajacy licznik
# ---------------------------------------------------------------------------
WORKFLOW = ".github/workflows/build.yml"

str_replace(
    WORKFLOW,
    """on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:""",
    """on:
  push:
    branches: [ main ]
  workflow_dispatch:

permissions:
  contents: write

jobs:""",
    "uprawnienia contents: write",
)

str_replace(
    WORKFLOW,
    """      - name: Build debug APK
        run: gradle assembleDebug

      - name: Upload APK""",
    """      - name: Build debug APK
        run: gradle assembleDebug

      # Numer wersji (1.0, 1.1, 1.2, ...) czytany jest przez Gradle z pliku
      # version.txt PRZED buildem. Tutaj, PO udanym buildzie, zwiekszamy ten
      # licznik o 1 i commitujemy z powrotem do repo, zeby kolejny build mial
      # kolejny numer. Push z domyslnym GITHUB_TOKEN nie odpala nowego
      # workflow (GitHub celowo to blokuje), wiec nie ma ryzyka petli.
      - name: Bump build version number
        run: |
          CURRENT=$(cat version.txt)
          NEXT=$((CURRENT + 1))
          echo "$NEXT" > version.txt
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add version.txt
          git commit -m "ci: bump build version to 1.$NEXT [skip ci]"
          git push

      - name: Upload APK""",
    "krok Bump build version number",
)

print("Wszystkie zmiany zastosowane pomyslnie.")
PYEOF

echo ""
echo "Gotowe."
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 59: simple incrementing version number (1.0, 1.1, 1.2, ...)\""
echo "  git push origin main"
echo "Potem poczekaj na zielony build — pierwszy build pokaze wersje 1.0, a workflow sam"
echo "zwiekszy licznik do 1 (commit 'ci: bump build version...') na potrzeby nastepnego builda."
