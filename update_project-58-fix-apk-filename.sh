#!/data/data/com.termux/files/usr/bin/bash
# Update 58: skaczany z GitHub Actions plik APK nazywal sie zawsze "app-debug.apk"
# (wg nazwy modulu Gradle), niezaleznie od android:label aplikacji ("FinArs").
# Teraz plik wyjsciowy bedzie nazywac sie np. "FinArs-1.2026.08.12-debug.apk".
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-58-fix-apk-filename.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update58_backup_${TS}"

echo "=== Update 58: nazwa pliku APK (app-debug.apk -> FinArs-<wersja>-debug.apk) ==="
echo "Przyczyna: Android Gradle Plugin domyslnie nazywa plik wyjsciowy wg nazwy"
echo "modulu (folder 'app'), a nie wg android:label aplikacji — dlatego kazdy"
echo "build sciagniety z GitHub Actions nazywal sie 'app-debug.apk'."
echo ""

if [ ! -f "app/build.gradle" ]; then
  echo "BLAD: nie widze app/build.gradle - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR/app"
mkdir -p "$BACKUP_DIR/.github/workflows"

cp "app/build.gradle" "$BACKUP_DIR/app/build.gradle"
cp ".github/workflows/build.yml" "$BACKUP_DIR/.github/workflows/build.yml"

echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

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
# 1) app/build.gradle — nadpisanie nazwy pliku wyjsciowego APK
# ---------------------------------------------------------------------------
GRADLE = "app/build.gradle"

str_replace(
    GRADLE,
    """    packagingOptions {
        resources {
            excludes += [
                'META-INF/DEPENDENCIES',
                'META-INF/LICENSE',
                'META-INF/LICENSE.txt',
                'META-INF/LICENSE.md',
                'META-INF/NOTICE',
                'META-INF/NOTICE.txt',
                'META-INF/NOTICE.md',
                'META-INF/*.kotlin_module'
            ]
        }
    }
}""",
    """    packagingOptions {
        resources {
            excludes += [
                'META-INF/DEPENDENCIES',
                'META-INF/LICENSE',
                'META-INF/LICENSE.txt',
                'META-INF/LICENSE.md',
                'META-INF/NOTICE',
                'META-INF/NOTICE.txt',
                'META-INF/NOTICE.md',
                'META-INF/*.kotlin_module'
            ]
        }
    }

    // Domyslnie AGP nazywa plik wyjsciowy wg nazwy modulu ("app-debug.apk"),
    // niezaleznie od android:label aplikacji — dlatego pobrany z GitHub Actions
    // plik zawsze nazywal sie "app-debug.apk", a nie "FinArs...". Nadpisujemy
    // nazwe pliku wyjsciowego dla kazdego wariantu.
    applicationVariants.all { variant ->
        variant.outputs.all { output ->
            outputFileName = "FinArs-${variant.versionName}-${variant.name}.apk"
        }
    }
}""",
    "nadpisanie nazwy pliku APK",
)

# ---------------------------------------------------------------------------
# 2) .github/workflows/build.yml — dopasowanie sciezki/nazwy artefaktu
# ---------------------------------------------------------------------------
WORKFLOW = ".github/workflows/build.yml"

str_replace(
    WORKFLOW,
    """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: app/build/outputs/apk/debug/app-debug.apk""",
    """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: FinArs-debug-apk
          path: app/build/outputs/apk/debug/FinArs-*-debug.apk""",
    "nazwa artefaktu + sciezka APK w workflow",
)

print("Wszystkie zmiany zastosowane pomyslnie.")
PYEOF

echo ""
echo "Gotowe."
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 58: fix downloaded APK filename (app-debug -> FinArs-<version>-debug)\""
echo "  git push origin main"
echo "Potem poczekaj na zielony build w zakladce Actions na GitHub — plik APK w artefakcie"
echo "bedzie sie teraz nazywac np. FinArs-1.2026.08.12-debug.apk zamiast app-debug.apk."
