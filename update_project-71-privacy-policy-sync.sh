#!/usr/bin/env bash
# update_project-71-privacy-policy-sync.sh  (FinArs)
# In-app Privacy Policy synced with https://apstudiomobile.pl/finars/privacy/ (October 5, 2026):
#  - new date in all 4 languages (en/pl/ru/uk)
#  - section 2: invoice PDFs are saved in Documents/FinArs/Invoices
#  - section 4: Google Play in-app update check
# Idempotent. Run BEFORE git add/commit/push.
set -e
cd "$(dirname "$0")"
[ -d app/src/main/res/values-pl ] || { echo "Run this script from the FinArs repo root"; exit 1; }

python3 - <<'PYEOF2'
import json, re
P = json.loads(r'''{"values": {"date": "Last updated: October 5, 2026", "s2": "Invoice PDF files created in the app are saved automatically in the Documents/FinArs/Invoices folder on your device; other apps you allow to access your files may be able to read them, and you can delete them at any time.", "s4": "Google Play (app updates) — the app may ask Google Play whether a newer version is available. No financial or business data is sent for this. Policy: policies.google.com/privacy"}, "values-pl": {"date": "Ostatnia aktualizacja: 5 października 2026 r.", "s2": "Pliki PDF faktur utworzone w aplikacji są zapisywane automatycznie w folderze Dokumenty/FinArs/Invoices na urządzeniu; inne aplikacje, którym zezwolisz na dostęp do plików, mogą je odczytać. Możesz je w każdej chwili usunąć.", "s4": "Google Play (aktualizacje aplikacji) — aplikacja może pytać Google Play, czy dostępna jest nowsza wersja. W tym celu nie są wysyłane żadne dane finansowe ani biznesowe. Polityka: policies.google.com/privacy"}, "values-ru": {"date": "Последнее обновление: 5 октября 2026 г.", "s2": "PDF-файлы счетов, созданные в приложении, автоматически сохраняются в папке Documents/FinArs/Invoices на устройстве; другие приложения, которым вы разрешите доступ к файлам, могут их прочитать, а вы можете удалить их в любой момент.", "s4": "Google Play (обновления приложения) — приложение может запрашивать у Google Play, доступна ли новая версия. Для этого никакие финансовые и бизнес-данные не передаются. Политика: policies.google.com/privacy"}, "values-uk": {"date": "Останнє оновлення: 5 жовтня 2026 р.", "s2": "PDF-файли рахунків, створені в застосунку, автоматично зберігаються в папці Documents/FinArs/Invoices на пристрої; інші застосунки, яким ви дозволите доступ до файлів, можуть їх прочитати, а ви можете видалити їх будь-коли.", "s4": "Google Play (оновлення застосунку) — застосунок може запитувати в Google Play, чи доступна нова версія. Для цього жодні фінансові та бізнес-дані не надсилаються. Політика: policies.google.com/privacy"}}''')
for d, x in P.items():
    f = "app/src/main/res/%s/strings.xml" % d
    s = open(f, encoding="utf-8").read()
    o = s
    s = re.sub(r'(<string name="privacy_updated_label">)(.*?)(</string>)',
               lambda m: m.group(1) + x["date"] + m.group(3), s, count=1, flags=re.S)
    def add(name, text, s):
        m = re.search(r'(<string-array name="%s">)(.*?)(\s*</string-array>)' % name, s, re.S)
        if not m or text in m.group(2):
            return s
        return s[:m.end(2)] + "\n        <item>" + text + "</item>" + s[m.end(2):]
    s = add("privacy_section2_bullets", x["s2"], s)
    s = add("privacy_section4_bullets", x["s4"], s)
    if s != o:
        open(f, "w", encoding="utf-8").write(s)
        print("updated", f)
    else:
        print("already OK", f)
PYEOF2
echo "Done. Now: git add -A && git commit -m 'Privacy policy sync' && git push"
