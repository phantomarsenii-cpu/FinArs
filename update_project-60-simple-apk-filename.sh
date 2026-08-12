#!/data/data/com.termux/files/usr/bin/bash
# Update 60: nazwa pobieranego pliku APK byla za dluga (np.
# "FinArs-1.2026.08.12-debug.apk"). Teraz plik bedzie mial prosta, stala
# nazwe: "FinArs.apk". Wersje aplikacji nadal widac wewnatrz samej appki
# (Ustawienia telefonu -> Aplikacje -> FinArs -> Wersja).
#
# Skrypt sam wykrywa, czy update_project-58-fix-apk-filename.sh zostal juz
# uruchomiony (i w jakiej wersji) i dopasowuje odpowiednia zamiane.
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-60-simple-apk-filename.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update60_backup_${TS}"

echo "=== Update 60: nazwa pliku APK -> zawsze 'FinArs.apk' (bez wersji/wariantu) ==="
echo ""

if [ ! -f "app/build.gradle" ] || [ ! -f ".github/workflows/build.yml" ]; then
  echo "BLAD: nie widze app/build.gradle lub .github/workflows/build.yml - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR/app"
mkdir -p "$BACKUP_DIR/.github/workflows"
cp "app/build.gradle" "$BACKUP_DIR/app/build.gradle"
cp ".github/workflows/build.yml" "$BACKUP_DIR/.github/workflows/build.yml"
echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

python3 << 'PYEOF'
import sys, re

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 1) app/build.gradle — outputFileName zawsze "FinArs.apk"
# ---------------------------------------------------------------------------
GRADLE = "app/build.gradle"

# Wariant A: update 58 jeszcze nie byl uruchomiony — brak bloku w ogole,
# dopisujemy go na koncu bloku android {...} (przed zamykajacym '}').
VARIANT_A_ANCHOR = """    packagingOptions {
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
}"""

# Wariant B: update 58 juz byl uruchomiony (nazwa z wersja/wariantem w nazwie).
VARIANT_B = """    // Domyslnie AGP nazywa plik wyjsciowy wg nazwy modulu ("app-debug.apk"),
    // niezaleznie od android:label aplikacji — dlatego pobrany z GitHub Actions
    // plik zawsze nazywal sie "app-debug.apk", a nie "FinArs...". Nadpisujemy
    // nazwe pliku wyjsciowego dla kazdego wariantu.
    applicationVariants.all { variant ->
        variant.outputs.all { output ->
            outputFileName = "FinArs-${variant.versionName}-${variant.name}.apk"
        }
    }
}"""

NEW_BLOCK = """    // Domyslnie AGP nazywa plik wyjsciowy wg nazwy modulu ("app-debug.apk"),
    // niezaleznie od android:label aplikacji. Nadpisujemy nazwe pliku
    // wyjsciowego na prosta, stala nazwe "FinArs.apk" (bez wersji/wariantu
    // w nazwie — sama wersja jest widoczna w samej aplikacji po instalacji).
    applicationVariants.all { variant ->
        variant.outputs.all { output ->
            outputFileName = "FinArs.apk"
        }
    }
}"""

with open(GRADLE, "r", encoding="utf-8") as f:
    content = f.read()

if NEW_BLOCK in content:
    print(f"Pominieto (juz zastosowano wczesniej): outputFileName FinArs.apk w {GRADLE}")
elif VARIANT_B in content:
    content = content.replace(VARIANT_B, NEW_BLOCK, 1)
    with open(GRADLE, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: outputFileName FinArs.apk (podmiana bloku update 58) -> {GRADLE}")
elif content.count(VARIANT_A_ANCHOR) == 1:
    content = content.replace(VARIANT_A_ANCHOR, VARIANT_A_ANCHOR[:-1] + "\n\n" + NEW_BLOCK, 1)
    with open(GRADLE, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: outputFileName FinArs.apk (nowy blok, update 58 nie byl uruchomiony) -> {GRADLE}")
else:
    print(f"BLAD: nie znalazlem znanego stanu bloku packagingOptions/applicationVariants w {GRADLE}")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2) .github/workflows/build.yml — sciezka do artefaktu
# ---------------------------------------------------------------------------
WORKFLOW = ".github/workflows/build.yml"

str_replace_any(
    WORKFLOW,
    [
        # update 58 juz zastosowany (glob z wersja)
        """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: FinArs-debug-apk
          path: app/build/outputs/apk/debug/FinArs-*-debug.apk""",
        # update 58 nie byl jeszcze zastosowany (oryginalna sciezka)
        """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: app/build/outputs/apk/debug/app-debug.apk""",
    ],
    """      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: FinArs-debug-apk
          path: app/build/outputs/apk/debug/FinArs.apk""",
    "sciezka do artefaktu FinArs.apk",
)

print("Wszystkie zmiany zastosowane pomyslnie.")
PYEOF

echo ""
echo "Gotowe."
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 60: simplify downloaded APK filename to FinArs.apk\""
echo "  git push origin main"
echo "Potem poczekaj na zielony build — plik do pobrania bedzie sie nazywac po prostu FinArs.apk."
