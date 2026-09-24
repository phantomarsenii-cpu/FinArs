#!/usr/bin/env bash
# Update 67: убрать мёртвый OCR чеков (ML Kit) -> уходит несовместимость с 16 KB
# страницами памяти; убрать ландшафтную блокировку zxing CaptureActivity -> уходит
# предупреждение про ограничения ориентации. Запускать из КОРНЯ репозитория.
set -euo pipefail

[ -f app/build.gradle ] || { echo "Запусти из корня репозитория (нет app/build.gradle)"; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
BK=".update67_backup_$TS"
J=app/src/main/java/com/example/fa_ksiegowy
mkdir -p "$BK/app/src/main/java/com/example/fa_ksiegowy" "$BK/.github/workflows"
cp app/build.gradle "$BK/app/build.gradle"
cp app/src/main/AndroidManifest.xml "$BK/app/AndroidManifest.xml"
cp .github/workflows/build.yml "$BK/.github/workflows/build.yml"
cp "$J/AddEntryActivity.kt" "$BK/app/src/main/java/com/example/fa_ksiegowy/"
[ -f "$J/ReceiptOcrHelper.kt" ] && cp "$J/ReceiptOcrHelper.kt" "$BK/app/src/main/java/com/example/fa_ksiegowy/"

# 1) ReceiptOcrHelper.kt — удалить
rm -f "$J/ReceiptOcrHelper.kt"

python3 - <<'PY'
import re, sys, io
J = "app/src/main/java/com/example/fa_ksiegowy"

def rw(path, fn):
    s = open(path, encoding="utf-8").read()
    n = fn(s)
    if n != s:
        open(path, "w", encoding="utf-8").write(n)
        print("изменён:", path)
    else:
        print("без изменений (уже применено):", path)

# 2) AddEntryActivity.kt — убрать OCR-код
def fix_activity(s):
    # a) поля + лаунчеры (takeOcrPhoto / pickOcrImage)
    a = s.find("    // Update: фото для распознавания чека (ML Kit OCR)")
    b = s.find("    override fun onCreate(savedInstanceState: Bundle?)")
    if a != -1 and b > a:
        s = s[:a] + s[b:]
    # b) launchReceiptScan / runOcr / buildReceiptComment
    a = s.find("    /** Запускает системную камеру для фото чека")
    b = s.find("    /** Открывает системный DatePickerDialog")
    if a != -1 and b > a:
        s = s[:a] + s[b:]
    # c) устаревший комментарий в шапке класса
    s = re.sub(r" \* Update: сканирование чека \(распознавание.*?\(см\. updateTypeToggleUi/runOcr\)\.\n \*\n",
               "", s, flags=re.S)
    return s
rw(f"{J}/AddEntryActivity.kt", fix_activity)

# 3) app/build.gradle — убрать ML Kit
def fix_gradle(s):
    return re.sub(r"\n    // Update 41: OCR чеков.*?\n    implementation \"com\.google\.mlkit:text-recognition:[^\"]+\"\n",
                  "\n", s, flags=re.S)
rw("app/build.gradle", fix_gradle)

# 4) AndroidManifest.xml — zxing CaptureActivity без sensorLandscape
def fix_manifest(s):
    if "com.journeyapps.barcodescanner.CaptureActivity" in s:
        return s
    if "xmlns:tools=" not in s:
        s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
                      '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"', 1)
    block = ('        <!-- zxing-android-embedded по умолчанию фиксирует sensorLandscape — Play Console\n'
             '             ругается на ограничения ориентации (Android 16 их игнорирует на больших экранах). -->\n'
             '        <activity android:name="com.journeyapps.barcodescanner.CaptureActivity"\n'
             '            android:screenOrientation="fullSensor"\n'
             '            tools:replace="android:screenOrientation" />\n')
    return s.replace("        <provider", block + "        <provider", 1)
rw("app/src/main/AndroidManifest.xml", fix_manifest)

# 5) setOrientationLocked(true) -> false (иначе скан снова блокирует ориентацию из кода)
for f in ("AddEditProductActivity.kt", "InventoryActivity.kt", "MagazinFragment.kt"):
    rw(f"{J}/{f}", lambda s: s.replace("setOrientationLocked(true)", "setOrientationLocked(false)"))

# 6) workflow — печатать нативные .so из AAB (после чистки должно быть пусто)
def fix_wf(s):
    if "Check native libs" in s:
        return s
    step = ('      - name: Check native libs in AAB (16 KB)\n'
            '        run: |\n'
            '          echo "=== .so in AAB ==="\n'
            '          unzip -l app/build/outputs/bundle/release/app-release.aab | grep "\\.so" || echo "no native libs"\n\n')
    return s.replace("      - name: Remove keystore file", step + "      - name: Remove keystore file", 1)
rw(".github/workflows/build.yml", fix_wf)
PY

echo "--- проверка ---"
grep -rn "mlkit\|ReceiptOcrHelper\|runOcr\|launchReceiptScan" app/src/main/java app/build.gradle && { echo "ОШИБКА: остались ссылки на OCR"; exit 1; } || echo "OCR-ссылок не осталось"
python3 - <<'PY'
import xml.dom.minidom, sys
xml.dom.minidom.parse("app/src/main/AndroidManifest.xml"); print("Manifest XML: OK")
s = open("app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt", encoding="utf-8").read()
code = "\n".join(l.split("//")[0] for l in s.splitlines())
print("Kotlin скобки { }:", code.count("{"), code.count("}"), "OK" if code.count("{")==code.count("}") else "ОШИБКА")
PY
echo "Готово. Бэкап: $BK"
