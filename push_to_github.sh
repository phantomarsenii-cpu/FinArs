#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# push_to_github.sh — коммит и пуш проекта FinArs (или любого) в GitHub из Termux
#
# ПЕРВЫЙ ЗАПУСК (один раз):
#   pkg install git
#   git config --global user.name "Твоё Имя"
#   git config --global user.email "твой@email.com"
#
# АВТОРИЗАЦИЯ (GitHub больше не принимает обычный пароль по HTTPS):
#   Создай Personal Access Token: https://github.com/settings/tokens
#   (Settings -> Developer settings -> Personal access tokens -> Fine-grained
#    или classic token с правом "repo")
#   При первом push Termux спросит логин/пароль — как "пароль" вставь токен.
#   Либо один раз сохрани токен, чтобы не вводить каждый раз:
#     git config --global credential.helper store
#   (после первого успешного push токен сохранится в ~/.git-credentials)
#
# ИСПОЛЬЗОВАНИЕ:
#   chmod +x push_to_github.sh
#   ./push_to_github.sh "текст коммита"
#
#   Если запустить без аргумента — коммит будет с автоматической меткой времени.
# ==============================================================================

set -euo pipefail

# --- НАСТРОЙ ПОД СЕБЯ ---------------------------------------------------------
PROJECT_DIR="$HOME/storage/shared/FA_ksiegowy-main"   # путь к папке проекта в Termux
REMOTE_URL="https://github.com/USERNAME/REPO.git"     # ссылка на твой репозиторий
BRANCH="main"                                          # ветка, в которую пушим
# -------------------------------------------------------------------------------

COMMIT_MSG="${1:-"Автообновление $(date '+%Y-%m-%d %H:%M:%S')"}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Папка проекта не найдена: $PROJECT_DIR"
  echo "   Открой этот файл и поправь переменную PROJECT_DIR под свой путь."
  exit 1
fi

cd "$PROJECT_DIR"

# Если это ещё не git-репозиторий — инициализируем и подключаем remote
if [ ! -d ".git" ]; then
  echo "ℹ️  Git-репозиторий не найден, инициализирую..."
  git init
  git branch -M "$BRANCH"
  git remote add origin "$REMOTE_URL"
else
  # Если remote уже есть, но указывает не туда — можно поправить вручную:
  #   git remote set-url origin "$REMOTE_URL"
  :
fi

echo "📦 Добавляю изменения..."
git add -A

# Если изменений нет — просто выходим без ошибки
if git diff --cached --quiet; then
  echo "✅ Нет изменений для коммита."
  exit 0
fi

echo "📝 Коммичу: $COMMIT_MSG"
git commit -m "$COMMIT_MSG"

echo "⬆️  Пушу в $REMOTE_URL ($BRANCH)..."
# Подтягиваем удалённые изменения, чтобы не было конфликта (rebase поверх своих)
git pull --rebase origin "$BRANCH" || true

git push -u origin "$BRANCH"

echo "🎉 Готово! Изменения запушены в $REMOTE_URL"
