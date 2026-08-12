#!/data/data/com.termux/files/usr/bin/bash
# Update 57: usuniecie wzmianki o JDG z ekranu "O aplikacji" oraz uproszczenie
# opisu Pro (usuniete PIT-36L / PIT-28 oraz zdanie o jednorazowym zakupie,
# bo teraz Pro bedzie subskrypcja).
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-57-about-jdg-and-pro-text.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update57_backup_${TS}"

echo "=== Update 57: tekst 'O aplikacji' (bez JDG) + tekst Pro (bez PIT-36L/PIT-28, bez 'jednorazowy zakup') ==="
echo "Co sie zmienia:"
echo "  1) about_intro (EN/PL/RU) — usunieta wzmianka o jednoosobowej dzialalnosci"
echo "     gospodarczej (JDG), bo aplikacja jest tylko dla dzialalnosci nierejestrowanej."
echo "  2) pro_info_message (EN/PL/RU) — usuniete 'PIT-36L / PIT-28' (zostaje tylko"
echo "     PIT-36) oraz usuniete zdanie 'To jednorazowy zakup...' (bo teraz Pro to"
echo "     subskrypcja, a nie zakup jednorazowy)."
echo ""

if [ ! -d "app/src/main/res/values" ]; then
  echo "BLAD: nie widze app/src/main/res/values - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR/app/src/main/res/values"
mkdir -p "$BACKUP_DIR/app/src/main/res/values-pl"
mkdir -p "$BACKUP_DIR/app/src/main/res/values-ru"

backup() {
  cp "$1" "$BACKUP_DIR/$1"
}

backup "app/src/main/res/values/strings.xml"
backup "app/src/main/res/values-pl/strings.xml"
backup "app/src/main/res/values-ru/strings.xml"

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
# 1) about_intro — usuniecie wzmianki o JDG
# ---------------------------------------------------------------------------
EN = "app/src/main/res/values/strings.xml"
PL = "app/src/main/res/values-pl/strings.xml"
RU = "app/src/main/res/values-ru/strings.xml"

str_replace(
    EN,
    '<string name="about_intro">FinArs is a comprehensive app for managing the finances of unregistered business activity and sole proprietorships (JDG). Track income and expenses,',
    '<string name="about_intro">FinArs is a comprehensive app for managing the finances of unregistered business activity. Track income and expenses,',
    "about_intro (EN) bez JDG",
)

str_replace(
    PL,
    '<string name="about_intro">FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej i jednoosobowej działalności gospodarczej (JDG). Śledź przychody i wydatki,',
    '<string name="about_intro">FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej. Śledź przychody i wydatki,',
    "about_intro (PL) bez JDG",
)

str_replace(
    RU,
    '<string name="about_intro">FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности и ИП (JDG). Ведите учёт доходов и расходов,',
    '<string name="about_intro">FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности. Ведите учёт доходов и расходов,',
    "about_intro (RU) bez JDG",
)

# ---------------------------------------------------------------------------
# 2) pro_info_message — usuniecie PIT-36L / PIT-28 i zdania o jednorazowym zakupie
# ---------------------------------------------------------------------------
str_replace(
    EN,
    '<string name="pro_info_message">Pro unlocks:\\n\\n\\u2022 Issuing invoices and receipts (PDF)\\n\\u2022 Yearly Excel report\\n\\u2022 Custom-period Excel report\\n\\u2022 PIT-36 / PIT-36L / PIT-28 tax return generation\\n\\u2022 Backup &amp; restore\\n\\u2022 No ads\\n\\nThis is a one-time purchase — pay once, keep it forever.</string>',
    '<string name="pro_info_message">Pro unlocks:\\n\\n\\u2022 Issuing invoices and receipts (PDF)\\n\\u2022 Yearly Excel report\\n\\u2022 Custom-period Excel report\\n\\u2022 PIT-36 tax return generation\\n\\u2022 Backup &amp; restore\\n\\u2022 No ads</string>',
    "pro_info_message (EN)",
)

str_replace(
    PL,
    '<string name="pro_info_message">Pro odblokowuje:\\n\\n\\u2022 Wystawianie faktur i rachunków (PDF)\\n\\u2022 Raport roczny w Excelu\\n\\u2022 Raport za dowolny okres\\n\\u2022 Generowanie deklaracji PIT-36 / PIT-36L / PIT-28\\n\\u2022 Kopia zapasowa i przywracanie danych\\n\\u2022 Brak reklam\\n\\nTo jednorazowy zakup — płacisz raz, dostęp zostaje na zawsze.</string>',
    '<string name="pro_info_message">Pro odblokowuje:\\n\\n\\u2022 Wystawianie faktur i rachunków (PDF)\\n\\u2022 Raport roczny w Excelu\\n\\u2022 Raport za dowolny okres\\n\\u2022 Generowanie deklaracji PIT-36\\n\\u2022 Kopia zapasowa i przywracanie danych\\n\\u2022 Brak reklam</string>',
    "pro_info_message (PL)",
)

str_replace(
    RU,
    '<string name="pro_info_message">Pro открывает:\\n\\n\\u2022 Выставление счетов и фактур (PDF)\\n\\u2022 Годовой отчёт в Excel\\n\\u2022 Отчёт за произвольный период\\n\\u2022 Формирование деклараций PIT-36 / PIT-36L / PIT-28\\n\\u2022 Резервное копирование и восстановление\\n\\u2022 Без рекламы\\n\\nЭто разовая покупка — платите один раз, доступ остаётся навсегда.</string>',
    '<string name="pro_info_message">Pro открывает:\\n\\n\\u2022 Выставление счетов и фактур (PDF)\\n\\u2022 Годовой отчёт в Excel\\n\\u2022 Отчёт за произвольный период\\n\\u2022 Формирование декларации PIT-36\\n\\u2022 Резервное копирование и восстановление\\n\\u2022 Без рекламы</string>',
    "pro_info_message (RU)",
)

print("Wszystkie zmiany zastosowane pomyslnie.")
PYEOF

echo ""
echo "Gotowe."
echo ""
echo "Nastepny krok (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 57: remove JDG mention from about text, simplify Pro description\""
echo "  git push origin main"
echo "Potem poczekaj na zielony build w zakladce Actions na GitHub i pobierz swiezy APK."
