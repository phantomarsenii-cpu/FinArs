#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# update_packagename.sh — меняет applicationId проекта FinArs на продакшен ID
#
# Что делает:
#   1. Меняет applicationId в app/build.gradle: com.example.fa_ksiegowy -> com.finars.app
#      (namespace / пакет Kotlin-кода НЕ трогается — это отдельная вещь от
#      applicationId, и её переименование потребовало бы переноса всех .kt
#      файлов в новую папку и правки package/import во всех классах. Задача
#      просит только сменить applicationId, поэтому namespace остаётся
#      com.example.fa_ksiegowy — это нормальная и рабочая конфигурация в
#      Android Gradle Plugin, никакой ошибки сборки это не вызывает).
#   2. Проверяет AndroidManifest.xml на жёстко прописанный старый пакет.
#      FileProvider уже использует ${applicationId}, поэтому подхватит новое
#      значение автоматически — но скрипт всё равно сканирует манифест и,
#      если найдёт литерал "com.example.fa_ksiegowy", заменит и его.
#   3. Пытается собрать debug-APK локально (./gradlew assembleDebug), чтобы
#      поймать конфликты импорта/сборки ДО коммита. Если в Termux нет
#      установленного Android SDK (частый случай — сборка тут обычно едет
#      через GitHub Actions, см. .github/workflows/build.yml), скрипт об этом
#      предупредит и спросит подтверждение, а не просто продолжит вслепую.
#   4. git add . / commit / push origin main.
#
# Запуск:
#   chmod +x update_packagename.sh
#   ./update_packagename.sh
#
# Скрипт нужно положить в корень проекта (там же, где app/build.gradle) и
# запускать оттуда, либо просто указать PROJECT_DIR ниже.
# ==============================================================================

set -euo pipefail

# --- НАСТРОЙ ПОД СЕБЯ ---------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"   # по умолчанию — папка со скриптом
BRANCH="main"
OLD_APP_ID="com.example.fa_ksiegowy"
NEW_APP_ID="com.finars.app"
COMMIT_MSG="Update applicationId to com.finars.app"
# -------------------------------------------------------------------------------

TS="$(date '+%Y%m%d_%H%M%S')"

echo "📂 Проект: $PROJECT_DIR"
cd "$PROJECT_DIR"

GRADLE_FILE="app/build.gradle"
MANIFEST_FILE="app/src/main/AndroidManifest.xml"

if [ ! -f "$GRADLE_FILE" ]; then
  echo "❌ Не найден $GRADLE_FILE. Запусти скрипт из корня проекта FinArs (или поправь PROJECT_DIR)."
  exit 1
fi

# --- 1. applicationId в app/build.gradle -------------------------------------
CURRENT_APP_ID="$(grep -oE 'applicationId\s+"[^"]+"' "$GRADLE_FILE" | head -1 | grep -oE '"[^"]+"' | tr -d '"')"

if [ "$CURRENT_APP_ID" = "$NEW_APP_ID" ]; then
  echo "ℹ️  applicationId уже установлен в $NEW_APP_ID, менять нечего."
elif [ "$CURRENT_APP_ID" != "$OLD_APP_ID" ]; then
  echo "⚠️  Текущий applicationId ($CURRENT_APP_ID) не совпадает с ожидаемым ($OLD_APP_ID)."
  echo "    Останавливаюсь, чтобы случайно не сломать чужую конфигурацию."
  exit 1
else
  cp "$GRADLE_FILE" "${GRADLE_FILE}.bak_${TS}"
  echo "🔧 Меняю applicationId: $OLD_APP_ID -> $NEW_APP_ID"
  # Точный таргет строки "applicationId "..."" — namespace-строку не трогаем
  sed -i "s/applicationId[[:space:]]\+\"$OLD_APP_ID\"/applicationId \"$NEW_APP_ID\"/" "$GRADLE_FILE"

  NEW_CHECK="$(grep -oE 'applicationId\s+"[^"]+"' "$GRADLE_FILE" | head -1)"
  if [[ "$NEW_CHECK" != *"$NEW_APP_ID"* ]]; then
    echo "❌ Замена applicationId не прошла, откатываю."
    mv "${GRADLE_FILE}.bak_${TS}" "$GRADLE_FILE"
    exit 1
  fi
  echo "✅ applicationId обновлён: $NEW_CHECK"
fi

# namespace должен остаться прежним — фиксируем это как факт, не как ошибку
NAMESPACE_LINE="$(grep -oE 'namespace\s+"[^"]+"' "$GRADLE_FILE" | head -1)"
echo "ℹ️  namespace не менялся: $NAMESPACE_LINE (это ожидаемо — см. комментарий вверху скрипта)"

# --- 2. Проверка/обновление AndroidManifest.xml -------------------------------
if [ -f "$MANIFEST_FILE" ]; then
  if grep -q '${applicationId}' "$MANIFEST_FILE"; then
    echo "✅ AndroidManifest.xml использует \${applicationId} (например, для FileProvider authorities) — подхватит новое значение автоматически."
  fi

  if grep -q "$OLD_APP_ID" "$MANIFEST_FILE"; then
    echo "🔧 Найден жёстко прописанный старый пакет в AndroidManifest.xml, заменяю..."
    cp "$MANIFEST_FILE" "${MANIFEST_FILE}.bak_${TS}"
    sed -i "s/$OLD_APP_ID/$NEW_APP_ID/g" "$MANIFEST_FILE"
    echo "✅ AndroidManifest.xml обновлён."
  else
    echo "✅ Жёстко прописанного старого applicationId ($OLD_APP_ID) в AndroidManifest.xml не найдено — менять нечего."
  fi
else
  echo "⚠️  $MANIFEST_FILE не найден, пропускаю проверку манифеста."
fi

# --- 3. Тестовая сборка --------------------------------------------------------
BUILD_OK=0
if [ -f "./gradlew" ]; then
  chmod +x ./gradlew
  echo "🏗️  Пробую тестовую сборку: ./gradlew assembleDebug"
  if ./gradlew assembleDebug --console=plain; then
    echo "✅ Тестовая сборка прошла успешно."
    BUILD_OK=1
  else
    echo "❌ Тестовая сборка упала."
  fi
else
  echo "⚠️  gradlew не найден рядом со скриптом — пропускаю локальную сборку."
fi

if [ "$BUILD_OK" -ne 1 ]; then
  echo ""
  echo "⚠️  Локальная сборка не подтверждена (нет Android SDK в Termux — это"
  echo "    частый случай, проект обычно собирается через GitHub Actions после"
  echo "    push, см. .github/workflows/build.yml)."
  read -r -p "Продолжить и всё равно закоммитить/запушить изменения? [y/N] " ANSWER
  case "$ANSWER" in
    y|Y|yes|Yes) echo "➡️  Продолжаю без подтверждённой локальной сборки." ;;
    *)
      echo "⛔ Останавливаюсь без коммита. Изменения в файлах остались на месте,"
      echo "   бэкапы лежат рядом с суффиксом .bak_${TS}."
      exit 1
      ;;
  esac
fi

# --- 4. git add / commit / push -----------------------------------------------
if [ ! -d ".git" ]; then
  echo "❌ Это не git-репозиторий (.git не найден в $PROJECT_DIR). Коммитить нечего."
  exit 1
fi

echo "📦 git add ."
git add .

if git diff --cached --quiet; then
  echo "✅ Нет изменений для коммита (файлы уже совпадают с последним коммитом)."
  exit 0
fi

echo "📝 git commit -m \"$COMMIT_MSG\""
git commit -m "$COMMIT_MSG"

echo "⬆️  git push origin $BRANCH"
git push origin "$BRANCH"

echo ""
echo "🎉 Готово! applicationId обновлён на $NEW_APP_ID и запушен в origin/$BRANCH."
