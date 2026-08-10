#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Update 55: fix — dolny pasek nawigacji renderowal sie na GORZE ekranu zamiast na dole ==="
echo ""
echo "Przyczyna: w <include layout=\"@layout/bottom_nav_bar\" android:layout_gravity=\"bottom\"/>"
echo "atrybut layout_gravity jest przez Android CALKOWICIE ignorowany, jesli na tym samym"
echo "tagu <include> nie sa RAZEM podane layout_width i layout_height. Przez to panel brai"
echo "wymiary z wlasnego roota bottom_nav_bar.xml (wrap_content) i domyslna grawitacje"
echo "FrameLayout (top|start) -> panel ladowal sie na samej gorze, pod pasek statusu."
echo ""

if [ ! -f "settings.gradle" ]; then
    echo "!!! Uruchom skrypt z korzenia projektu (tam, gdzie jest settings.gradle)"
    exit 1
fi

FILES="app/src/main/res/layout/activity_report.xml app/src/main/res/layout/activity_history.xml app/src/main/res/layout/activity_mine.xml app/src/main/res/layout/activity_settings.xml"

BACKUP_DIR=".update55_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in $FILES; do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Backup zapisany w $BACKUP_DIR ---"

CHANGED=0
for f in $FILES; do
    if [ -f "$f" ] && grep -q '<include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>' "$f"; then
        sed -i 's#<include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>#<include layout="@layout/bottom_nav_bar"\n        android:layout_width="match_parent"\n        android:layout_height="wrap_content"\n        android:layout_gravity="bottom"/>#' "$f"
        echo "Naprawiono: $f"
        CHANGED=$((CHANGED+1))
    else
        echo "Pominieto (juz naprawione albo brak wzorca): $f"
    fi
done

echo ""
if [ "$CHANGED" -eq 0 ]; then
    echo "Nic nie trzeba bylo zmieniac — patch juz zastosowany wczesniej."
else
    echo "Gotowe. Naprawiono $CHANGED plik(ow)."
fi
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 55: fix bottom nav bar rendering at top instead of bottom\""
echo "  git push origin main"
echo "Potem poczekaj na zielony build w zakladce Actions na GitHub i pobierz swiezy APK."
