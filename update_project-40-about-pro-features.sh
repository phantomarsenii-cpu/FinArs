#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 40: полный список функций в \"O aplikacji\" и в окне Pro ==="
echo "Что меняется:"
echo " - Раздел \"O aplikacji\" (О приложении): полный, красиво оформленный список всех возможностей"
echo " - Окно \"Pro\": добавлены недостающие пункты (фактуры, PIT-36/36L/28)"
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

BACKUP_DIR=".update40_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-ru/strings.xml" \
    "app/src/main/res/values-pl/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"

echo ""
echo "--- Обновляю строки ---"

if [ -f "app/src/main/res/values/strings.xml" ]; then
    python3 - << 'PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_STRINGS_XML'
import re
path = "app/src/main/res/values/strings.xml"
text = open(path, encoding='utf-8').read()
new_about_description = 'FinArs is a comprehensive app for managing the finances of unregistered business activity and sole proprietorships (JDG). Track income and expenses, monitor limits, automatically calculate taxes, issue invoices, and generate ready-made reports and tax returns — all in one place, with the full history of operations always at hand.\\n\\n\\uD83D\\uDCCA Finances and taxes\\n\\uD83D\\uDCB0 Income and expense tracking with attached receipts\\n\\uD83D\\uDCC8 Automatic profit and tax calculation (12%/32% scale, 19% flat, lump-sum)\\n\\uD83D\\uDD01 Recurring transactions (rent, subscriptions) created automatically every month\\n\\uD83D\\uDEA6 Limit tracking: unregistered activity, 120,000 zł tax bracket, VAT exemption (200,000 zł)\\n\\uD83D\\uDD14 Notifications when limits are approaching or exceeded\\n\\n\\uD83E\\uDDFE Invoices and receipts (Pro)\\n\\uD83D\\uDCDD Issue invoices/receipts to individuals and companies with PDF generation\\n\\u2705 Statuses: Paid / Pending / Overdue, plus due-date reminders\\n\\uD83D\\uDCB5 Tracking of the annual 20,000 zł cash-sales limit for private individuals\\n\\uD83D\\uDD0D Invoice history with search and filters\\n\\n\\uD83D\\uDCC4 Reports and tax returns\\n\\uD83D\\uDCCA Income/expense chart for the last 6 months\\n\\uD83D\\uDCE5 Export monthly report (free), yearly and custom-period reports (Pro) to Excel with receipts\\n\\uD83E\\uDDEE Generate PIT-36 / PIT-36L / PIT-28 tax returns — helper PDF and official form filling (Pro)\\n\\n\\uD83D\\uDD12 Security and convenience\\n\\uD83D\\uDD10 App lock with PIN code and fingerprint / face unlock\\n\\uD83D\\uDCBE Backup and restore your data (Pro)\\n\\uD83C\\uDF19 Modern dark interface\\n\\uD83C\\uDF0D Available in Polish, Russian and English\\n\\uD83D\\uDD12 All data is stored locally on your device\\n\\nContact: p.arsenii@interia.pl'
text = re.sub(r'<string name="about_description">.*?</string>', lambda m: '<string name="about_description">' + new_about_description + '</string>', text, count=1, flags=re.DOTALL)
new_pro_info_message = 'Pro unlocks:\\n\\n\\u2022 Issuing invoices and receipts (PDF)\\n\\u2022 Yearly Excel report\\n\\u2022 Custom-period Excel report\\n\\u2022 PIT-36 / PIT-36L / PIT-28 tax return generation\\n\\u2022 Backup &amp; restore\\n\\u2022 No ads\\n\\nThis is a one-time purchase — pay once, keep it forever.'
text = re.sub(r'<string name="pro_info_message">.*?</string>', lambda m: '<string name="pro_info_message">' + new_pro_info_message + '</string>', text, count=1, flags=re.DOTALL)
open(path, 'w', encoding='utf-8').write(text)
PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_STRINGS_XML
    echo "OK: app/src/main/res/values/strings.xml"
else
    echo "skip: app/src/main/res/values/strings.xml not found"
fi

if [ -f "app/src/main/res/values-ru/strings.xml" ]; then
    python3 - << 'PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML'
import re
path = "app/src/main/res/values-ru/strings.xml"
text = open(path, encoding='utf-8').read()
new_about_description = 'FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности и ИП (JDG). Ведите учёт доходов и расходов, контролируйте лимиты, автоматически считайте налоги, выставляйте счета и формируйте готовые отчёты и налоговые декларации — всё в одном месте, с полной историей операций под рукой.\\n\\n\\uD83D\\uDCCA Финансы и налоги\\n\\uD83D\\uDCB0 Учёт доходов и расходов с прикреплением чеков\\n\\uD83D\\uDCC8 Автоматический расчёт прибыли и налога (шкала 12%/32%, плоский 19%, ryczałt)\\n\\uD83D\\uDD01 Регулярные транзакции (аренда, подписки) создаются автоматически каждый месяц\\n\\uD83D\\uDEA6 Контроль лимитов: незарегистрированная деятельность, порог 120 000 zł, освобождение от VAT (200 000 zł)\\n\\uD83D\\uDD14 Уведомления о приближении и превышении лимитов\\n\\n\\uD83E\\uDDFE Счета и фактуры (Pro)\\n\\uD83D\\uDCDD Выставление счетов/фактур физлицам и компаниям с генерацией PDF\\n\\u2705 Статусы: Оплачена / Ожидает оплаты / Просрочена, плюс напоминания о сроке оплаты\\n\\uD83D\\uDCB5 Контроль годового лимита наличных (20 000 zł) для продаж физлицам\\n\\uD83D\\uDD0D История счетов с поиском и фильтрами\\n\\n\\uD83D\\uDCC4 Отчёты и декларации\\n\\uD83D\\uDCCA График доходов и расходов за последние 6 месяцев\\n\\uD83D\\uDCE5 Экспорт отчёта за месяц (бесплатно), год и произвольный период (Pro) в Excel вместе с чеками\\n\\uD83E\\uDDEE Формирование деклараций PIT-36 / PIT-36L / PIT-28 — вспомогательный PDF и заполнение официального бланка (Pro)\\n\\n\\uD83D\\uDD12 Безопасность и удобство\\n\\uD83D\\uDD10 Блокировка приложения PIN-кодом и отпечатком пальца / лицом\\n\\uD83D\\uDCBE Резервное копирование и восстановление данных (Pro)\\n\\uD83C\\uDF19 Современный тёмный интерфейс\\n\\uD83C\\uDF0D Доступно на польском, русском и английском языках\\n\\uD83D\\uDD12 Все данные хранятся локально на устройстве\\n\\nСвязь: p.arsenii@interia.pl'
text = re.sub(r'<string name="about_description">.*?</string>', lambda m: '<string name="about_description">' + new_about_description + '</string>', text, count=1, flags=re.DOTALL)
new_pro_info_message = 'Pro открывает:\\n\\n\\u2022 Выставление счетов и фактур (PDF)\\n\\u2022 Годовой отчёт в Excel\\n\\u2022 Отчёт за произвольный период\\n\\u2022 Формирование деклараций PIT-36 / PIT-36L / PIT-28\\n\\u2022 Резервное копирование и восстановление\\n\\u2022 Без рекламы\\n\\nЭто разовая покупка — платите один раз, доступ остаётся навсегда.'
text = re.sub(r'<string name="pro_info_message">.*?</string>', lambda m: '<string name="pro_info_message">' + new_pro_info_message + '</string>', text, count=1, flags=re.DOTALL)
open(path, 'w', encoding='utf-8').write(text)
PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML
    echo "OK: app/src/main/res/values-ru/strings.xml"
else
    echo "skip: app/src/main/res/values-ru/strings.xml not found"
fi

if [ -f "app/src/main/res/values-pl/strings.xml" ]; then
    python3 - << 'PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML'
import re
path = "app/src/main/res/values-pl/strings.xml"
text = open(path, encoding='utf-8').read()
new_about_description = 'FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej i jednoosobowej działalności gospodarczej (JDG). Śledź przychody i wydatki, kontroluj limity, automatycznie licz podatki, wystawiaj faktury i generuj gotowe raporty oraz deklaracje PIT — wszystko w jednym miejscu, z pełną historią operacji zawsze pod ręką.\\n\\n\\uD83D\\uDCCA Finanse i podatki\\n\\uD83D\\uDCB0 Ewidencja przychodów i wydatków z załącznikami paragonów\\n\\uD83D\\uDCC8 Automatyczne obliczanie zysku i podatku (skala 12%/32%, liniowy 19%, ryczałt)\\n\\uD83D\\uDD01 Transakcje cykliczne (czynsz, abonamenty) tworzone automatycznie co miesiąc\\n\\uD83D\\uDEA6 Kontrola limitów: działalność nierejestrowana, próg 120 000 zł, zwolnienie z VAT (200 000 zł)\\n\\uD83D\\uDD14 Powiadomienia o zbliżających się i przekroczonych limitach\\n\\n\\uD83E\\uDDFE Faktury i rachunki (Pro)\\n\\uD83D\\uDCDD Wystawianie faktur/rachunków dla osób fizycznych i firm z generowaniem PDF\\n\\u2705 Statusy: Zapłacona / Oczekuje na zapłatę / Zaległa, plus przypomnienia o terminie płatności\\n\\uD83D\\uDCB5 Kontrola rocznego limitu gotówki (20 000 zł) dla sprzedaży osobom fizycznym\\n\\uD83D\\uDD0D Historia faktur z wyszukiwaniem i filtrami\\n\\n\\uD83D\\uDCC4 Raporty i deklaracje\\n\\uD83D\\uDCCA Wykres przychodów i wydatków za ostatnie 6 miesięcy\\n\\uD83D\\uDCE5 Eksport raportu miesięcznego (bezpłatnie), rocznego i za dowolny okres (Pro) do Excela wraz z paragonami\\n\\uD83E\\uDDEE Generowanie deklaracji PIT-36 / PIT-36L / PIT-28 — pomocniczy PDF oraz wypełnienie oficjalnego formularza (Pro)\\n\\n\\uD83D\\uDD12 Bezpieczeństwo i wygoda\\n\\uD83D\\uDD10 Blokada aplikacji kodem PIN oraz odciskiem palca / twarzą\\n\\uD83D\\uDCBE Kopia zapasowa i przywracanie danych (Pro)\\n\\uD83C\\uDF19 Nowoczesny ciemny interfejs\\n\\uD83C\\uDF0D Dostępne w języku polskim, rosyjskim i angielskim\\n\\uD83D\\uDD12 Wszystkie dane są przechowywane lokalnie na urządzeniu\\n\\nKontakt: p.arsenii@interia.pl'
text = re.sub(r'<string name="about_description">.*?</string>', lambda m: '<string name="about_description">' + new_about_description + '</string>', text, count=1, flags=re.DOTALL)
new_pro_info_message = 'Pro odblokowuje:\\n\\n\\u2022 Wystawianie faktur i rachunków (PDF)\\n\\u2022 Raport roczny w Excelu\\n\\u2022 Raport za dowolny okres\\n\\u2022 Generowanie deklaracji PIT-36 / PIT-36L / PIT-28\\n\\u2022 Kopia zapasowa i przywracanie danych\\n\\u2022 Brak reklam\\n\\nTo jednorazowy zakup — płacisz raz, dostęp zostaje na zawsze.'
text = re.sub(r'<string name="pro_info_message">.*?</string>', lambda m: '<string name="pro_info_message">' + new_pro_info_message + '</string>', text, count=1, flags=re.DOTALL)
open(path, 'w', encoding='utf-8').write(text)
PYEOF_UPDATE40_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML
    echo "OK: app/src/main/res/values-pl/strings.xml"
else
    echo "skip: app/src/main/res/values-pl/strings.xml not found"
fi

echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) git add -A && git commit -m 'Update 40: full feature list in About and Pro screens' && git push"
echo "2) Дождись сборки в GitHub Actions и проверь экран Ustawienia -> O aplikacji, и окно Pro"
echo ""
echo "Бэкап изменённых файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
