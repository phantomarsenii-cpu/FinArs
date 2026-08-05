#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 26: восстановлена точка входа в PIT-36 (Pro) из Settings ==="
echo "Строки settings_menu_pit36 / pit36_pro_locked_message были подготовлены во всех"
echo "3 локализациях, Pit36Activity зарегистрирована в манифесте — но нигде в UI не было"
echo "кнопки, которая её открывает. Экран (выбор года, генерация PDF, редактирование"
echo "личных данных для PIT-36) был полностью недостижим. Добавляем кнопку в Settings"
echo "по образцу уже существующей кнопки Backup (Pro-gate + диалог с переходом на покупку)."
echo ""

APP_DIR="app/src/main/java/com/example/fa_ksiegowy"
RES_DIR="app/src/main/res/layout"

LAYOUT_FILE="$RES_DIR/activity_settings.xml"
KT_FILE="$APP_DIR/SettingsActivity.kt"

if [ ! -f "$LAYOUT_FILE" ] || [ ! -f "$KT_FILE" ]; then
    echo "!!! Не найдены ожидаемые файлы ($LAYOUT_FILE / $KT_FILE)."
    echo "!!! Запускайте скрипт из корня проекта (FA_ksiegowy-main)."
    exit 1
fi

# --- 1) Layout: добавляем кнопку btn_menu_pit36 сразу после btn_menu_tax ---
if grep -q 'btn_menu_pit36' "$LAYOUT_FILE"; then
    echo "OK: кнопка btn_menu_pit36 в layout уже есть, пропускаю."
else
    python3 - "$LAYOUT_FILE" << 'EOF_PY'
import sys, io

path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

anchor = '''    <Button android:id="@+id/btn_menu_tax" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_tax" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>
'''

insertion = anchor + '''
    <Button android:id="@+id/btn_menu_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_pit36" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>
'''

if anchor not in content:
    print("!!! Не найден якорь btn_menu_tax в " + path)
    sys.exit(1)

content = content.replace(anchor, insertion, 1)

with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: кнопка btn_menu_pit36 добавлена в " + path)
EOF_PY
fi

# --- 2) SettingsActivity.kt: обработчик клика ---
if grep -q 'btn_menu_pit36' "$KT_FILE"; then
    echo "OK: обработчик btn_menu_pit36 в SettingsActivity.kt уже есть, пропускаю."
else
    python3 - "$KT_FILE" << 'EOF_PY'
import sys, io

path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

anchor = '''        findViewById<Button>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(this, SettingsLanguageActivity::class.java))
        }'''

insertion = '''        findViewById<Button>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
''' + anchor

if anchor not in content:
    print("!!! Не найден якорь btn_menu_language в " + path)
    sys.exit(1)

content = content.replace(anchor, insertion, 1)

with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: обработчик btn_menu_pit36 добавлен в " + path)
EOF_PY
fi

echo ""
echo "=== Готово. Пересоберите проект (./gradlew assembleDebug) и проверьте: ==="
echo "Settings -> 'Сформировать PIT-36 (Pro)' -> для Pro открывает Pit36Activity,"
echo "для не-Pro показывает диалог с переходом на экран покупки Pro."
