#!/bin/bash
#
# apply_update_36.sh
# ============================================================================
# Мастер-скрипт обновления FinArs #36.
# Делает всё за один запуск:
#   1. Бэкапит файлы, которые будут изменены
#   2. Распаковывает finars_complete_update_36_tar.gz (если найден рядом)
#   3. Запускает update_project-36-fix-spouse-fields-and-tax-limits-crash.sh
#   4. Копирует Pit36LCalculator.kt, Pit28Calculator.kt, EDeklaracjeXmlGenerator.kt
#      в app/src/main/java/com/example/fa_ksiegowy/
#   5. (опционально) собирает проект: ./gradlew assembleDebug
#   6. (опционально) коммитит и пушит изменения в git (для Termux)
#
# Использование:
#   chmod +x apply_update_36.sh
#   ./apply_update_36.sh /path/to/FA_ksiegowy-main
#   ./apply_update_36.sh /path/to/FA_ksiegowy-main --build
#   ./apply_update_36.sh /path/to/FA_ksiegowy-main --build --push
#   ./apply_update_36.sh /path/to/FA_ksiegowy-main --push -m "Update 36: spouse fields + tax fix"
#
# Все флаги необязательны и могут комбинироваться. Без флагов скрипт только
# применяет патчи и копирует файлы — сборку и git оставляет вам.
# ============================================================================

set -uo pipefail

# ---------- цвета для читаемости в Termux ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[ОШИБКА]${NC} $1"; exit 1; }

# ---------- разбор аргументов ----------
PROJECT_ROOT=""
DO_BUILD=0
DO_PUSH=0
COMMIT_MSG="Update 36: spouse fields, tax-limits crash fix, PIT-36L/PIT-28 calculators, e-Deklaracje XML"

while [ $# -gt 0 ]; do
    case "$1" in
        --build) DO_BUILD=1; shift ;;
        --push) DO_PUSH=1; shift ;;
        -m) COMMIT_MSG="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^#//'
            exit 0
            ;;
        *)
            if [ -z "$PROJECT_ROOT" ]; then PROJECT_ROOT="$1"; else fail "Неизвестный аргумент: $1"; fi
            shift
            ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || fail "Путь к проекту не найден: аргумент №1 должен указывать на FA_ksiegowy-main"

JAVA_SRC="$PROJECT_ROOT/app/src/main/java/com/example/fa_ksiegowy"
RES_SRC="$PROJECT_ROOT/app/src/main/res"

info "Проект: $PROJECT_ROOT"

# ---------- проверка, что это тот самый проект ----------
[ -d "$JAVA_SRC" ] || fail "Не найдена директория $JAVA_SRC — проверьте, что указан правильный корень проекта FA_ksiegowy-main"
[ -f "$JAVA_SRC/TermsActivity.kt" ] || fail "Не найден TermsActivity.kt — похоже, это не проект FA_ksiegowy"

# ---------- директория, где лежит сам этот скрипт и пакет обновления ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

FIX_SCRIPT="update_project-36-fix-spouse-fields-and-tax-limits-crash.sh"
CALC_FILES=("Pit36LCalculator.kt" "Pit28Calculator.kt" "EDeklaracjeXmlGenerator.kt")

# Если файлов пакета нет рядом — попробовать распаковать архив
if [ ! -f "$FIX_SCRIPT" ] && [ -f "finars_complete_update_36_tar.gz" ]; then
    info "Распаковываю finars_complete_update_36_tar.gz..."
    tar -xzf finars_complete_update_36_tar.gz
fi

[ -f "$FIX_SCRIPT" ] || fail "Не найден $FIX_SCRIPT рядом со скриптом. Положите apply_update_36.sh в ту же папку, что и файлы пакета обновления 36 (или архив finars_complete_update_36_tar.gz)."
for f in "${CALC_FILES[@]}"; do
    [ -f "$f" ] || fail "Не найден $f рядом со скриптом."
done

# ---------- бэкап файлов, которые будут затронуты ----------
BACKUP_DIR="$PROJECT_ROOT/.update36_backup_$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$BACKUP_DIR"
info "Бэкап изменяемых файлов -> $BACKUP_DIR"

BACKUP_TARGETS=(
    "$RES_SRC/values/strings.xml"
    "$RES_SRC/values-pl/strings.xml"
    "$RES_SRC/values-ru/strings.xml"
    "$RES_SRC/layout/activity_settings_tax.xml"
    "$RES_SRC/layout/activity_pit36.xml"
    "$JAVA_SRC/SettingsTaxActivity.kt"
    "$JAVA_SRC/Pit36Activity.kt"
    "$JAVA_SRC/TermsActivity.kt"
)
for f in "${BACKUP_TARGETS[@]}"; do
    if [ -f "$f" ]; then
        rel="${f#"$PROJECT_ROOT"/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp "$f" "$BACKUP_DIR/$rel"
    fi
done
ok "Бэкап готов"

# ---------- шаг 1: запуск фикс-скрипта #36 ----------
info "Применяю update_project-36 (крэш SettingsTax, поля супруга, TermsActivity)..."
chmod +x "$FIX_SCRIPT"
if ./"$FIX_SCRIPT" "$PROJECT_ROOT"; then
    ok "update_project-36 применён"
else
    fail "update_project-36 завершился с ошибкой — проверьте вывод выше. Бэкап лежит в $BACKUP_DIR"
fi

# ---------- шаг 2: копирование калькуляторов и XML-генератора ----------
info "Копирую Pit36LCalculator.kt, Pit28Calculator.kt, EDeklaracjeXmlGenerator.kt..."
for f in "${CALC_FILES[@]}"; do
    cp "$f" "$JAVA_SRC/$f"
    ok "  -> $JAVA_SRC/$f"
done

echo ""
ok "Все файлы обновления #36 применены."
echo ""

# ---------- шаг 3 (опционально): сборка ----------
if [ "$DO_BUILD" -eq 1 ]; then
    info "Собираю проект (./gradlew clean assembleDebug)..."
    (
        cd "$PROJECT_ROOT"
        if [ -x "./gradlew" ]; then
            chmod +x ./gradlew
            ./gradlew clean assembleDebug
        else
            warn "gradlew не найден или не исполняемый — сборка пропущена"
        fi
    )
    if [ $? -eq 0 ]; then
        ok "Сборка прошла успешно"
    else
        warn "Сборка завершилась с ошибкой — проверьте вывод Gradle выше"
    fi
fi

# ---------- шаг 4 (опционально): git commit + push ----------
if [ "$DO_PUSH" -eq 1 ]; then
    (
        cd "$PROJECT_ROOT"
        if [ ! -d ".git" ]; then
            warn "В $PROJECT_ROOT нет .git — пропускаю коммит/push"
            exit 0
        fi
        info "git add / commit / push..."
        git add -A
        if git diff --cached --quiet; then
            warn "Нет изменений для коммита"
        else
            git commit -m "$COMMIT_MSG"
            CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
            git push origin "$CURRENT_BRANCH"
            ok "Изменения запушены в origin/$CURRENT_BRANCH"
        fi
    )
fi

echo ""
echo "============================================================================"
ok "ГОТОВО. Обновление #36 применено к $PROJECT_ROOT"
echo "============================================================================"
echo "Бэкап оригиналов: $BACKUP_DIR"
echo ""
echo "Что проверить руками перед релизом:"
echo "  - Settings -> \"Налог и лимиты\" (не должно крашить)"
echo "  - PIT-36: чекбокс \"Совместная подача с супругом\" и появление полей"
echo "  - После TermsActivity показывается выбор типа деятельности"
echo ""
if [ "$DO_BUILD" -eq 0 ]; then
    echo "Сборка не запускалась (нет флага --build). Запустите вручную:"
    echo "  cd $PROJECT_ROOT && ./gradlew clean assembleDebug"
fi
if [ "$DO_PUSH" -eq 0 ]; then
    echo "Git push не выполнялся (нет флага --push). Запустите вручную или добавьте --push:"
    echo "  cd $PROJECT_ROOT && git add -A && git commit -m \"$COMMIT_MSG\" && git push"
fi
echo "============================================================================"
