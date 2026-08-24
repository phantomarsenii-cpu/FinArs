#!/data/data/com.termux/files/usr/bin/bash
# Update 63: stawka VAT NA KAZDEJ POZYCJI faktury (zamiast jednej wspolnej stawki na
# cala fakture) — rozne towary/uslugi moga miec rozne stawki VAT na jednym dokumencie.
#
# Zmiany:
#  1) InvoiceItem ma teraz wlasne pole vatRate (migracja bazy v11 -> v12, kolumna
#     invoice_items.vatRate, NULL dla juz istniejacych pozycji).
#  2) AddInvoiceActivity: usuniety globalny przycisk "Stawka VAT" (jeden na cala
#     fakture) — zamiast niego kazdy WIERSZ pozycji ma wlasny przycisk stawki VAT
#     (widoczny tylko gdy sprzedawca jest juz zarejestrowanym platnikiem VAT, czyli
#     compliance.requiresVatRateSelection == true), dokladnie tak jak juz dzialajaca
#     kategoria ryczaltu na pozycji. Walidacja przy wystawianiu wymaga stawki na
#     KAZDEJ pozycji.
#  3) InvoiceHtmlPdfGenerator: tabela pozycji liczy Netto/VAT/Brutto WEDLUG WLASNEJ
#     stawki kazdej pozycji, dodaje blok "W tym" (rozbicie sum wg stawek — tylko gdy
#     pozycje faktycznie maja rozne stawki) i wiersz "Razem" (laczne netto/VAT/brutto),
#     zgodnie ze wzorem dostarczonym przez uzytkownika. Ta sama logika dziala tez w
#     Faktura korygujaca (before/after tabele).
#  4) NAPRAWIONY BLAD: zielony pasek "DO ZAPLATY" pokazywal kwote NETTO nawet gdy VAT
#     obowiazywal — teraz poprawnie pokazuje BRUTTO (netto+VAT), z trzema linijkami
#     Wartosc netto/VAT/brutto nad paskiem.
#
# WYMAGANIA: uruchamiac PO update_project-62 (korzysta z tego samego layoutu korekty).
# Jesli update-62 nie byl jeszcze zastosowany, ten skrypt sam to wykryje i przerwie.
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-63-per-item-vat.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update63_backup_${TS}"

echo "=== Update 63: stawka VAT na kazdej pozycji faktury ==="
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
  echo "BLAD: nie widze settings.gradle lub app/src/main/java/com/example/fa_ksiegowy - uruchom skrypt z korzenia repo."
  exit 1
fi

if grep -q "val vatRate: String? = null" "app/src/main/java/com/example/fa_ksiegowy/InvoiceItem.kt" 2>/dev/null; then
  echo "!!! Wyglada na to, ze update_project-63 zostal juz zastosowany (InvoiceItem.kt ma juz pole vatRate)."
  exit 1
fi

if ! grep -q "correctedItems: Map<Int, Double>" "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt" 2>/dev/null; then
  echo "BLAD: nie widac update_project-62 (korekta wielu pozycji) w InvoiceHtmlPdfGenerator.kt."
  echo "Uruchom najpierw: bash update_project-62-korekta-multi-item-and-wave-fade.sh"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceItem.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/res/values/ids.xml" \
    "app/src/main/res/layout/item_invoice_line.xml" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/assets/invoice_template.html" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "Kopia zapasowa zapisana w: $BACKUP_DIR"
echo ""

echo "-> punktowe patche (Python, idempotentne), krok 1/5: InvoiceHtmlPdfGenerator.kt (tabela z VAT per-pozycja + W tym + Razem)"
python3 << 'PYEOF_PDFGEN'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    # Zaden "stary" fragment nie pasuje — albo juz zastosowano wczesniej (nowy fragment
    # juz jest w pliku), albo cos poszlo nie tak. Sprawdzamy DOPIERO TERAZ (nie na wstepie!),
    # bo "new" bywa fragmentem/podciagiem tekstu, ktory i tak juz istnieje w nietknietym
    # pliku (np. kontekstowa linia po usunietym bloku) — wczesniejsze sprawdzenie dawaloby
    # falszywie pozytywny "already applied" i CICHO POMIJALO patch przy pierwszym uruchomieniu.
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

GEN = "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt"

# ---------------------------------------------------------------------------
# 1) Row: dodajemy pole vatRate — stawka VAT TEJ KONKRETNEJ pozycji (wcześniej
#    stawka byla WSPOLNA dla calej faktury, przekazywana osobnym parametrem).
# ---------------------------------------------------------------------------
OLD_ROW = "    private data class Row(val name: String, val qty: Double, val unitPrice: Double)"
NEW_ROW = """    // Update 63: Row ma teraz WLASNA stawke VAT (wczesniej jedna stawka byla wspolna dla
    // calej faktury) — rozne pozycje moga miec rozne stawki (towar 23%, ksiazka 5% itd.),
    // dokladnie jak w prawdziwej fakturze VAT z wieloma stawkami na jednym dokumencie.
    private data class Row(val name: String, val qty: Double, val unitPrice: Double, val vatRate: VatRate? = null)"""
str_replace_any(GEN, [OLD_ROW], NEW_ROW, "Row: dodanie pola vatRate")

# ---------------------------------------------------------------------------
# 2) generate(): budowa rows z WLASNA stawka VAT kazdej pozycji (item.vatRate),
#    zamiast jednej wspolnej vatRate na cala fakture; netTotal/vatTotal do
#    buildSumRow (naprawia "DO ZAPLATY" pokazujace kwote netto zamiast brutto,
#    gdy VAT obowiazuje).
# ---------------------------------------------------------------------------
OLD_GEN_BODY = """        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }"""
NEW_GEN_BODY = """        // Update 63: kazda pozycja ma teraz WLASNA stawke VAT (InvoiceItem.vatRate) —
        // rozne towary/uslugi na jednej fakturze moga byc opodatkowane roznymi stawkami.
        // Parametr vatRate ponizej to juz tylko FALLBACK dla przypadku brzegowego (items
        // puste, pojedyncza pozycja z serviceName/amount) — w normalnym przebiegu (zawsze,
        // patrz AddInvoiceActivity) items nie jest puste.
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            else listOf(Row(serviceName, 1.0, amount, vatRate))
        val netTotal = rows.sumOf { it.qty * it.unitPrice }
        val vatTotal = rows.sumOf { row -> row.vatRate?.vatAmount(row.qty * row.unitPrice) ?: 0.0 }"""
str_replace_any(GEN, [OLD_GEN_BODY], NEW_GEN_BODY, "generate(): rows z per-pozycja VAT + netTotal/vatTotal")

OLD_GEN_TABLE_CALL = """        val itemsTableHtml = "<div class=\\"table-with-total\\">" +
            buildItemsTable(context, null, rows, vatRate) +
            buildSumRow(context, totalAmount, vatRate != null) +
            "</div>\""""
NEW_GEN_TABLE_CALL = """        val itemsTableHtml = "<div class=\\"table-with-total\\">" +
            buildItemsTable(context, null, rows) +
            buildSumRow(context, netTotal, vatTotal, rows.any { it.vatRate != null }) +
            "</div>\""""
str_replace_any(GEN, [OLD_GEN_TABLE_CALL], NEW_GEN_TABLE_CALL, "generate(): wywolanie buildItemsTable/buildSumRow bez wspolnej vatRate")

# ---------------------------------------------------------------------------
# 3) generateCorrection(): beforeRows/afterRows tez per-pozycja VAT (stawka
#    danej pozycji NIE zmienia sie przy korekcie — zmienia sie tylko kwota).
# ---------------------------------------------------------------------------
OLD_CORR_ROWS = """        val fallbackLabel = "${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber"
        val beforeRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(fallbackLabel, 1.0, originalAmount))

        val afterRows: List<Row> = when {
            correctedItems.isNotEmpty() -> {
                items.mapIndexed { idx, item ->
                    val newValue = correctedItems[idx]
                    if (newValue != null) {
                        val newUnitPrice = if (item.quantity != 0.0) newValue / item.quantity else newValue
                        Row(item.name, item.quantity, newUnitPrice)
                    } else {
                        Row(item.name, item.quantity, item.unitPrice)
                    }
                }
            }
            items.isNotEmpty() -> {
                val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
                items.map { Row(it.name, it.quantity, it.unitPrice * scale) }
            }
            else -> listOf(Row(fallbackLabel, 1.0, correctedAmount))
        }

        val tablesHtml = StringBuilder()
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_before_table_title), beforeRows, vatRate))
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_after_table_title), afterRows, vatRate))"""
NEW_CORR_ROWS = """        val fallbackLabel = "${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber"
        // Update 63: stawka VAT KAZDEJ pozycji (item.vatRate) nie zmienia sie przy korekcie —
        // korekta zmienia tylko kwote, dlatego before/after rows dziedziczy te sama stawke
        // co oryginalna pozycja.
        val beforeRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            else listOf(Row(fallbackLabel, 1.0, originalAmount, vatRate))

        val afterRows: List<Row> = when {
            correctedItems.isNotEmpty() -> {
                items.mapIndexed { idx, item ->
                    val itemVat = VatRate.fromStorageKeyOrNull(item.vatRate)
                    val newValue = correctedItems[idx]
                    if (newValue != null) {
                        val newUnitPrice = if (item.quantity != 0.0) newValue / item.quantity else newValue
                        Row(item.name, item.quantity, newUnitPrice, itemVat)
                    } else {
                        Row(item.name, item.quantity, item.unitPrice, itemVat)
                    }
                }
            }
            items.isNotEmpty() -> {
                val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
                items.map { Row(it.name, it.quantity, it.unitPrice * scale, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            }
            else -> listOf(Row(fallbackLabel, 1.0, correctedAmount, vatRate))
        }

        val tablesHtml = StringBuilder()
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_before_table_title), beforeRows))
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_after_table_title), afterRows))"""
str_replace_any(GEN, [OLD_CORR_ROWS], NEW_CORR_ROWS, "generateCorrection(): before/afterRows z per-pozycja VAT")

# ---------------------------------------------------------------------------
# 4) buildItemsTable(): pelny rewrite — kazda pozycja liczona wg WLASNEJ stawki
#    (row.vatRate), blok "W tym" (rozbicie wg stawek, tylko gdy >1 roznych
#    stawek wsrod pozycji) i wiersz "Razem" (suma netto/VAT/brutto), zgodnie z
#    wzorem dostarczonym przez uzytkownika.
# ---------------------------------------------------------------------------
OLD_BUILD_TABLE = '''    /** Buduje tabelę pozycji — bez VAT (Lp/Nazwa/Jedn./Ilość/Cena netto/Wartość netto, jak
     *  na dostarczonym makiecie) lub z VAT (dodatkowo Stawka VAT/Kwota VAT/Wartość brutto),
     *  dokładnie ta sama logika kolumn co w InvoicePdfGenerator — tylko jako <table> HTML. */
    private fun buildItemsTable(context: Context, title: String?, rows: List<Row>, vatRate: VatRate?): String {
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }

        val sb = StringBuilder()
        if (title != null) sb.append("<div class=\\"table-title\\">${esc(title)}</div>")
        sb.append("<table class=\\"items\\"><thead><tr>")
        sb.append("<th class=\\"col-lp\\">${esc(context.getString(R.string.invoice_pdf_table_lp))}</th>")
        sb.append("<th class=\\"col-name\\">${esc(context.getString(R.string.invoice_pdf_table_name))}</th>")
        sb.append("<th class=\\"col-unit\\">${esc(context.getString(R.string.invoice_pdf_table_unit))}</th>")
        sb.append("<th class=\\"col-qty num\\">${esc(context.getString(R.string.invoice_pdf_table_qty))}</th>")
        if (vatRate == null) {
            sb.append("<th class=\\"col-price num\\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\\"col-total num\\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
        } else {
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_vat_rate))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_brutto))}</th>")
        }
        sb.append("</tr></thead><tbody>")

        val vatRateShort = vatRate?.percent?.let { p -> val i = p.toInt(); if (i.toDouble() == p) "$i%" else "$p%" } ?: vatRate?.storageKey

        rows.forEachIndexed { idx, row ->
            sb.append("<tr>")
            sb.append("<td>${idx + 1}</td>")
            sb.append("<td>${esc(row.name)}</td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_unit_piece))}</td>")
            sb.append("<td class=\\"num\\">${qtyStr(row.qty)}</td>")
            if (vatRate == null) {
                sb.append("<td class=\\"num\\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\\"num\\">${money(row.qty * row.unitPrice)}</td>")
            } else {
                val netValue = row.qty * row.unitPrice
                val vatAmount = vatRate.vatAmount(netValue)
                val bruttoValue = netValue + vatAmount
                sb.append("<td class=\\"num\\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\\"num\\">${money(netValue)}</td>")
                sb.append("<td class=\\"num\\">${vatRateShort}</td>")
                sb.append("<td class=\\"num\\">${money(vatAmount)}</td>")
                sb.append("<td class=\\"num\\">${money(bruttoValue)}</td>")
            }
            sb.append("</tr>")
        }
        sb.append("</tbody></table>")
        return sb.toString()
    }'''

NEW_BUILD_TABLE = '''    /** Buduje tabelę pozycji — bez VAT (Lp/Nazwa/Jedn./Ilość/Cena netto/Wartość netto, jak
     *  na dostarczonym makiecie) lub z VAT (dodatkowo Stawka VAT/Kwota VAT/Wartość brutto).
     *  Update 63: stawka VAT jest teraz WŁASNOŚCIĄ KAŻDEJ POZYCJI (row.vatRate) zamiast
     *  jednej wspólnej stawki na całą fakturę — różne towary/usługi mogą mieć różne stawki
     *  na jednym dokumencie. Tabela pokazuje kolumny VAT, jeśli CHOĆ JEDNA pozycja ma
     *  ustawioną stawkę. Gdy wśród pozycji występuje więcej niż jedna różna stawka VAT,
     *  pod pozycjami dodawany jest blok "W tym" (podsumowanie netto/VAT/brutto osobno dla
     *  każdej stawki) oraz wiersz "Razem" (łączne netto/VAT/brutto) — dokładnie jak w
     *  standardowej fakturze VAT z wieloma stawkami. */
    private fun buildItemsTable(context: Context, title: String?, rows: List<Row>): String {
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val vatLabel: (VatRate?) -> String = { rate ->
            if (rate == null) "—"
            else rate.percent?.let { p -> val i = p.toInt(); if (i.toDouble() == p) "$i%" else "$p%" } ?: rate.storageKey
        }

        val hasVat = rows.any { it.vatRate != null }

        val sb = StringBuilder()
        if (title != null) sb.append("<div class=\\"table-title\\">${esc(title)}</div>")
        sb.append("<table class=\\"items\\"><thead><tr>")
        sb.append("<th class=\\"col-lp\\">${esc(context.getString(R.string.invoice_pdf_table_lp))}</th>")
        sb.append("<th class=\\"col-name\\">${esc(context.getString(R.string.invoice_pdf_table_name))}</th>")
        sb.append("<th class=\\"col-unit\\">${esc(context.getString(R.string.invoice_pdf_table_unit))}</th>")
        sb.append("<th class=\\"col-qty num\\">${esc(context.getString(R.string.invoice_pdf_table_qty))}</th>")
        if (!hasVat) {
            sb.append("<th class=\\"col-price num\\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\\"col-total num\\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
        } else {
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_vat_rate))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</th>")
            sb.append("<th class=\\"num\\">${esc(context.getString(R.string.invoice_pdf_table_brutto))}</th>")
        }
        sb.append("</tr></thead><tbody>")

        var sumNet = 0.0
        var sumVat = 0.0
        // Suma wg stawki VAT — do bloku "W tym" (klucz = etykieta stawki, np. "23%").
        val byRate = LinkedHashMap<String, DoubleArray>()

        rows.forEachIndexed { idx, row ->
            val netValue = row.qty * row.unitPrice
            sumNet += netValue
            sb.append("<tr>")
            sb.append("<td>${idx + 1}</td>")
            sb.append("<td>${esc(row.name)}</td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_unit_piece))}</td>")
            sb.append("<td class=\\"num\\">${qtyStr(row.qty)}</td>")
            if (!hasVat) {
                sb.append("<td class=\\"num\\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\\"num\\">${money(netValue)}</td>")
            } else {
                val vatAmount = row.vatRate?.vatAmount(netValue) ?: 0.0
                val bruttoValue = netValue + vatAmount
                sumVat += vatAmount
                val rateLabel = vatLabel(row.vatRate)
                sb.append("<td class=\\"num\\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\\"num\\">${money(netValue)}</td>")
                sb.append("<td class=\\"num\\">${rateLabel}</td>")
                sb.append("<td class=\\"num\\">${money(vatAmount)}</td>")
                sb.append("<td class=\\"num\\">${money(bruttoValue)}</td>")
                val bucket = byRate.getOrPut(rateLabel) { DoubleArray(3) }
                bucket[0] += netValue; bucket[1] += vatAmount; bucket[2] += bruttoValue
            }
            sb.append("</tr>")
        }
        sb.append("</tbody>")

        if (hasVat) {
            // Blok "W tym": tylko gdy pozycje faktycznie mają różne stawki — przy jednej
            // wspólnej stawce dublowałby wiersz "Razem" poniżej bez żadnej nowej informacji.
            if (byRate.size > 1) {
                var first = true
                for ((rateLabel, sums) in byRate) {
                    sb.append("<tr class=\\"vat-breakdown-row\\">")
                    sb.append("<td colspan=\\"4\\"></td>")
                    sb.append("<td>${if (first) esc(context.getString(R.string.invoice_pdf_vat_breakdown_label)) else ""}</td>")
                    sb.append("<td class=\\"num\\">${money(sums[0])}</td>")
                    sb.append("<td class=\\"num\\">${rateLabel}</td>")
                    sb.append("<td class=\\"num\\">${money(sums[1])}</td>")
                    sb.append("<td class=\\"num\\">${money(sums[2])}</td>")
                    sb.append("</tr>")
                    first = false
                }
            }
            val grossTotal = sumNet + sumVat
            sb.append("<tr class=\\"vat-total-row\\">")
            sb.append("<td colspan=\\"4\\"></td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_table_total))}</td>")
            sb.append("<td class=\\"num\\">${money(sumNet)}</td>")
            sb.append("<td></td>")
            sb.append("<td class=\\"num\\">${money(sumVat)}</td>")
            sb.append("<td class=\\"num\\">${money(grossTotal)}</td>")
            sb.append("</tr>")
        }

        sb.append("</table>")
        return sb.toString()
    }'''
str_replace_any(GEN, [OLD_BUILD_TABLE], NEW_BUILD_TABLE, "buildItemsTable(): per-pozycja VAT + blok W tym + Razem")

# ---------------------------------------------------------------------------
# 5) buildSumRow(): dodaje 3 linijki Wartość netto/VAT/brutto NAD zielonym
#    paskiem "DO ZAPŁATY", i NAPRAWIA sam pasek — pokazywał kwotę NETTO nawet
#    gdy VAT obowiązywał (parametr isVat w ogóle nie był używany w treści
#    funkcji) — teraz "DO ZAPŁATY" to poprawnie kwota BRUTTO (netto+VAT), gdy
#    VAT obowiązuje.
# ---------------------------------------------------------------------------
OLD_SUM_ROW = '''    private fun buildSumRow(context: Context, totalAmount: Double, isVat: Boolean): String {
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        return """
            <div class="sum-row">
              <div class="sum-label-wrap">${esc(context.getString(R.string.invoice_pdf_sum_label))} DO ZAPŁATY</div>
              <div class="sum-amount">${money(totalAmount)}</div>
            </div>
        """.trimIndent()
    }'''
NEW_SUM_ROW = '''    private fun buildSumRow(context: Context, netTotal: Double, vatTotal: Double, hasVat: Boolean): String {
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val grossTotal = netTotal + vatTotal
        // Update 63: gdy VAT obowiązuje, "DO ZAPŁATY" to kwota BRUTTO (netto+VAT) — wcześniej
        // ten pasek zawsze pokazywał samo netto, nawet dla faktur z VAT, co było błędem
        // (kupujący płaci netto+VAT, nie samo netto). Trzy linijki netto/VAT/brutto nad
        // paskiem pokazują pełne rozliczenie, tak jak w dostarczonym wzorze.
        val breakdownHtml = if (hasVat) """
            <div class="totals-breakdown">
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_netto))}</span><b>${money(netTotal)}</b></div>
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</span><b>${money(vatTotal)}</b></div>
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_brutto))}</span><b>${money(grossTotal)}</b></div>
            </div>
        """.trimIndent() else ""
        return """
            $breakdownHtml
            <div class="sum-row">
              <div class="sum-label-wrap">${esc(context.getString(R.string.invoice_pdf_sum_label))} DO ZAPŁATY</div>
              <div class="sum-amount">${money(if (hasVat) grossTotal else netTotal)}</div>
            </div>
        """.trimIndent()
    }'''
str_replace_any(GEN, [OLD_SUM_ROW], NEW_SUM_ROW, "buildSumRow(): rozbicie netto/VAT/brutto + naprawa DO ZAPLATY na brutto")

print("")
print("Wszystkie patche InvoiceHtmlPdfGenerator.kt zastosowane pomyslnie.")
PYEOF_PDFGEN

echo "-> krok 2/5: invoice_template.html (style CSS dla wierszy VAT/Razem/podsumowania)"
python3 << 'PYEOF_CSS'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    # Zaden "stary" fragment nie pasuje — albo juz zastosowano wczesniej (nowy fragment
    # juz jest w pliku), albo cos poszlo nie tak. Sprawdzamy DOPIERO TERAZ (nie na wstepie!),
    # bo "new" bywa fragmentem/podciagiem tekstu, ktory i tak juz istnieje w nietknietym
    # pliku (np. kontekstowa linia po usunietym bloku) — wczesniejsze sprawdzenie dawaloby
    # falszywie pozytywny "already applied" i CICHO POMIJALO patch przy pierwszym uruchomieniu.
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

TPL = "app/src/main/assets/invoice_template.html"

OLD = """  .sum-amount{
    background:var(--green-bg);
    color:#FFFFFF;
    font-size:14pt; font-weight:800;
    padding:2.2mm 6mm;
    border-radius:2mm;
    min-width:28mm; text-align:center;
  }

  /* --- korekta: blok przyczyny + podsumowanie kwot --- */"""
NEW = """  .sum-amount{
    background:var(--green-bg);
    color:#FFFFFF;
    font-size:14pt; font-weight:800;
    padding:2.2mm 6mm;
    border-radius:2mm;
    min-width:28mm; text-align:center;
  }

  /* Update 63: wiersze rozbicia VAT wewnatrz table.items — blok "W tym" (osobne stawki)
     i wiersz "Razem" (laczne netto/VAT/brutto), widoczne tylko gdy pozycje faktury maja
     rozne stawki VAT (patrz InvoiceHtmlPdfGenerator.buildItemsTable). */
  .vat-breakdown-row td{
    font-size:9pt; color:#666666; font-style:italic;
    border-top:none;
  }
  .vat-total-row td{
    font-size:9.5pt; font-weight:800; color:var(--text);
    border-top:0.9pt solid var(--grid);
  }

  /* Update 63: trzy linijki Wartosc netto/VAT/brutto nad zielonym paskiem "DO ZAPLATY",
     widoczne tylko gdy VAT obowiazuje (patrz InvoiceHtmlPdfGenerator.buildSumRow). */
  .totals-breakdown{
    padding:2.5mm 4mm 0 4mm; background:#FFFFFF;
  }
  .totals-line{
    display:flex; justify-content:space-between; align-items:center;
    font-size:9.5pt; color:var(--text); padding:0.8mm 0;
  }

  /* --- korekta: blok przyczyny + podsumowanie kwot --- */"""
str_replace_any(TPL, [OLD], NEW, "CSS: .vat-breakdown-row / .vat-total-row / .totals-breakdown")
PYEOF_CSS

echo "-> krok 3/5: AddInvoiceActivity.kt (stawka VAT na kazdej pozycji zamiast jednej wspolnej)"
python3 << 'PYEOF_ACT'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    # Zaden "stary" fragment nie pasuje — albo juz zastosowano wczesniej (nowy fragment
    # juz jest w pliku), albo cos poszlo nie tak. Sprawdzamy DOPIERO TERAZ (nie na wstepie!),
    # bo "new" bywa fragmentem/podciagiem tekstu, ktory i tak juz istnieje w nietknietym
    # pliku (np. kontekstowa linia po usunietym bloku) — wczesniejsze sprawdzenie dawaloby
    # falszywie pozytywny "already applied" i CICHO POMIJALO patch przy pierwszym uruchomieniu.
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

ACT = "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"

# 1) usuniecie globalnej zmiennej selectedVatRate — stawka jest teraz WLASNOSCIA KAZDEJ
#    pozycji (tag_vat_rate na wierszu), nie jednym wyborem na cala fakture.
OLD_FIELD = """    /** Stan limitu VAT/kasy fiskalnej — odświeżany w onCreate/onResume (zob. refreshComplianceStatus). */
    private var compliance: VatComplianceHelper.ComplianceStatus? = null
    private var selectedVatRate: VatRate? = null"""
NEW_FIELD = """    /** Stan limitu VAT/kasy fiskalnej — odświeżany w onCreate/onResume (zob. refreshComplianceStatus). */
    private var compliance: VatComplianceHelper.ComplianceStatus? = null
    // Update 63: stawka VAT jest teraz wybierana OSOBNO NA KAŻDEJ POZYCJI faktury (przycisk
    // btn_item_vat_rate na każdym wierszu, wartość w tag_vat_rate) — różne towary/usługi
    // mogą mieć różne stawki na jednej fakturze. Usunięto pojedynczy wybór na całą fakturę
    // (dawne selectedVatRate/btn_vat_rate)."""
str_replace_any(ACT, [OLD_FIELD], NEW_FIELD, "usuniecie selectedVatRate (pole klasy)")

# 2) onCreate(): usuniecie listenera globalnego przycisku btn_vat_rate (przycisk usuniety z layoutu).
OLD_ONCREATE_VAT_BTN = """        findViewById<Button>(R.id.btn_vat_rate).setOnClickListener { showVatRatePicker() }

        findViewById<Button>(R.id.btn_upload_logo).setOnClickListener {"""
NEW_ONCREATE_VAT_BTN = """        findViewById<Button>(R.id.btn_upload_logo).setOnClickListener {"""
str_replace_any(ACT, [OLD_ONCREATE_VAT_BTN], NEW_ONCREATE_VAT_BTN, "onCreate(): usuniecie listenera btn_vat_rate")

# 3) refreshComplianceStatus(): zamiast pokazywac/chowac JEDEN globalny przycisk stawki VAT,
#    odswiezamy widocznosc przycisku VAT NA KAZDYM WIERSZU pozycji (patrz refreshAllItemRowsVatVisibility).
OLD_COMPLIANCE_VAT = """                val btnVatRate = findViewById<Button>(R.id.btn_vat_rate)
                if (status.requiresVatRateSelection) {
                    btnVatRate.visibility = View.VISIBLE
                    refreshVatRateButtonText()
                } else {
                    btnVatRate.visibility = View.GONE
                    selectedVatRate = null
                }

                findViewById<View>(R.id.row_is_receipt).visibility ="""
NEW_COMPLIANCE_VAT = """                // Update 63: stawka VAT jest teraz per-pozycja (patrz addItemRow) — tu tylko
                // pokazujemy/chowamy podpowiedź nad listą pozycji i odświeżamy widoczność
                // przycisku stawki NA KAŻDYM już istniejącym wierszu (dodane PRZED tym, jak
                // status zdążył się załadować asynchronicznie, np. pierwszy pusty wiersz z onCreate).
                findViewById<View>(R.id.tv_vat_rate_info).visibility =
                    if (status.requiresVatRateSelection) View.VISIBLE else View.GONE
                refreshAllItemRowsVatVisibility()

                findViewById<View>(R.id.row_is_receipt).visibility ="""
str_replace_any(ACT, [OLD_COMPLIANCE_VAT], NEW_COMPLIANCE_VAT, "refreshComplianceStatus(): per-pozycja VAT zamiast jednego przycisku")

# 4) usuniecie refreshVatRateButtonText()/showVatRatePicker() (globalne) — zastapione przez
#    odpowiedniki per-pozycja (refreshItemVatButtonText/otwieranie w addItemRow).
OLD_GLOBAL_VAT_FUNCS = """    private fun refreshVatRateButtonText() {
        val btn = findViewById<Button>(R.id.btn_vat_rate)
        val rate = selectedVatRate
        btn.text = if (rate != null) getString(R.string.vat_rate_selected, getString(rate.labelResId))
        else getString(R.string.vat_rate_choose)
    }

    private fun showVatRatePicker() {
        AppDialog.showOptionPicker(
            context = this,
            title = getString(R.string.vat_rate_picker_title),
            options = VatRate.entries.map { it.storageKey to getString(it.labelResId) }
        ) { selected ->
            selectedVatRate = VatRate.fromStorageKeyOrNull(selected)
            refreshVatRateButtonText()
        }
    }

    /** Кнопка "Dodaj towary z magazynu\""""
NEW_GLOBAL_VAT_FUNCS = """    /** Кнопка "Dodaj towary z magazynu\""""
str_replace_any(ACT, [OLD_GLOBAL_VAT_FUNCS], NEW_GLOBAL_VAT_FUNCS, "usuniecie globalnych refreshVatRateButtonText()/showVatRatePicker()")

# 5) addItemRow(): dodanie przycisku stawki VAT NA TEJ POZYCJI, analogicznie do kategorii
#    ryczaltu — widoczny tylko gdy sprzedawca jest juz podatnikiem VAT (compliance).
OLD_ADDITEMROW_CATEGORY = """        val btnCategory = row.findViewById<Button>(R.id.btn_item_ryczalt_category)
        if (activityType == ActivityType.JDG_RYCZALT) {
            btnCategory.visibility = View.VISIBLE
            refreshItemCategoryButtonText(row, btnCategory)
            btnCategory.setOnClickListener {
                AppDialog.showOptionPicker(
                    context = this,
                    title = getString(R.string.ryczalt_category_picker_title),
                    options = RyczaltCategory.entries.map { it.name to getString(it.labelRes) }
                ) { selected ->
                    row.setTag(R.id.tag_ryczalt_category, selected)
                    refreshItemCategoryButtonText(row, btnCategory)
                }
            }
        } else {
            btnCategory.visibility = View.GONE
        }

        val watcher = object : android.text.TextWatcher {"""
NEW_ADDITEMROW_CATEGORY = """        val btnCategory = row.findViewById<Button>(R.id.btn_item_ryczalt_category)
        if (activityType == ActivityType.JDG_RYCZALT) {
            btnCategory.visibility = View.VISIBLE
            refreshItemCategoryButtonText(row, btnCategory)
            btnCategory.setOnClickListener {
                AppDialog.showOptionPicker(
                    context = this,
                    title = getString(R.string.ryczalt_category_picker_title),
                    options = RyczaltCategory.entries.map { it.name to getString(it.labelRes) }
                ) { selected ->
                    row.setTag(R.id.tag_ryczalt_category, selected)
                    refreshItemCategoryButtonText(row, btnCategory)
                }
            }
        } else {
            btnCategory.visibility = View.GONE
        }

        // Update 63: stawka VAT TEJ KONKRETNEJ pozycji — widoczna tylko gdy sprzedawca jest
        // już zarejestrowanym podatnikiem VAT (compliance.requiresVatRateSelection); różne
        // pozycje na jednej fakturze mogą mieć różne stawki (patrz InvoiceHtmlPdfGenerator).
        val btnVat = row.findViewById<Button>(R.id.btn_item_vat_rate)
        refreshItemVatButtonVisibility(btnVat)
        refreshItemVatButtonText(row, btnVat)
        btnVat.setOnClickListener {
            AppDialog.showOptionPicker(
                context = this,
                title = getString(R.string.vat_rate_picker_title),
                options = VatRate.entries.map { it.storageKey to getString(it.labelResId) }
            ) { selected ->
                row.setTag(R.id.tag_vat_rate, selected)
                refreshItemVatButtonText(row, btnVat)
            }
        }

        val watcher = object : android.text.TextWatcher {"""
str_replace_any(ACT, [OLD_ADDITEMROW_CATEGORY], NEW_ADDITEMROW_CATEGORY, "addItemRow(): przycisk stawki VAT na pozycji")

# 6) nowe funkcje pomocnicze — obok istniejacego refreshItemCategoryButtonText.
OLD_HELPERS = """    private fun refreshItemCategoryButtonText(row: View, btn: Button) {
        val cat = RyczaltCategory.fromStorageKeyOrNull(row.getTag(R.id.tag_ryczalt_category) as? String)
        btn.text = if (cat != null) getString(R.string.ryczalt_category_selected, getString(cat.labelRes))
        else getString(R.string.ryczalt_category_choose)
    }

    private fun renumberItemRows() {"""
NEW_HELPERS = """    private fun refreshItemCategoryButtonText(row: View, btn: Button) {
        val cat = RyczaltCategory.fromStorageKeyOrNull(row.getTag(R.id.tag_ryczalt_category) as? String)
        btn.text = if (cat != null) getString(R.string.ryczalt_category_selected, getString(cat.labelRes))
        else getString(R.string.ryczalt_category_choose)
    }

    private fun refreshItemVatButtonVisibility(btn: Button) {
        btn.visibility = if (compliance?.requiresVatRateSelection == true) View.VISIBLE else View.GONE
    }

    private fun refreshItemVatButtonText(row: View, btn: Button) {
        val rate = VatRate.fromStorageKeyOrNull(row.getTag(R.id.tag_vat_rate) as? String)
        btn.text = if (rate != null) getString(R.string.vat_rate_selected, getString(rate.labelResId))
        else getString(R.string.vat_rate_choose)
    }

    /** Wywoływane po (asynchronicznym) odświeżeniu compliance — pierwszy pusty wiersz
     *  pozycji jest dodawany w onCreate ZANIM status zdąży się załadować, więc jego
     *  przycisk stawki VAT trzeba doświetlić/dociemnić dopiero teraz. */
    private fun refreshAllItemRowsVatVisibility() {
        val container = findViewById<LinearLayout>(R.id.ll_invoice_items)
        for (i in 0 until container.childCount) {
            refreshItemVatButtonVisibility(container.getChildAt(i).findViewById(R.id.btn_item_vat_rate))
        }
    }

    private fun renumberItemRows() {"""
str_replace_any(ACT, [OLD_HELPERS], NEW_HELPERS, "nowe funkcje refreshItemVatButtonVisibility/Text/refreshAllItemRowsVatVisibility")

# 7) InvoiceLineInput: dodanie pola vatRate (storageKey z tagu wiersza).
OLD_LINE_INPUT = """    private data class InvoiceLineInput(
        val name: String,
        val qty: Double,
        val price: Double,
        val category: String?,
        val productId: Long?
    )"""
NEW_LINE_INPUT = """    private data class InvoiceLineInput(
        val name: String,
        val qty: Double,
        val price: Double,
        val category: String?,
        val productId: Long?,
        // Update 63: stawka VAT (storageKey VatRate) TEJ KONKRETNEJ pozycji — patrz
        // btn_item_vat_rate/tag_vat_rate w addItemRow().
        val vatRate: String?
    )"""
str_replace_any(ACT, [OLD_LINE_INPUT], NEW_LINE_INPUT, "InvoiceLineInput: dodanie pola vatRate")

OLD_COLLECT = """            result.add(
                InvoiceLineInput(
                    name = name,
                    qty = if (qty == null || qty <= 0.0) 1.0 else qty,
                    price = price,
                    category = row.getTag(R.id.tag_ryczalt_category) as? String,
                    productId = row.getTag(R.id.tag_product_id) as? Long
                )
            )"""
NEW_COLLECT = """            result.add(
                InvoiceLineInput(
                    name = name,
                    qty = if (qty == null || qty <= 0.0) 1.0 else qty,
                    price = price,
                    category = row.getTag(R.id.tag_ryczalt_category) as? String,
                    productId = row.getTag(R.id.tag_product_id) as? Long,
                    vatRate = row.getTag(R.id.tag_vat_rate) as? String
                )
            )"""
str_replace_any(ACT, [OLD_COLLECT], NEW_COLLECT, "collectItemRows(): odczyt tag_vat_rate")

# 8) generateInvoice(): walidacja per-pozycja (zamiast jednego globalnego wyboru) + budowa
#    InvoiceItem z wlasna stawka + Invoice.vatRate = wspolna stawka JESLI wszystkie pozycje
#    maja te sama (dla zgodnosci wstecznej/podgladu), inaczej null (mieszane stawki).
OLD_VALIDATION = """        // Sprzedawca jest już podatnikiem VAT — stawka VAT jest obowiązkowa na każdej fakturze.
        if (compliance?.requiresVatRateSelection == true && selectedVatRate == null) {
            Toast.makeText(this, getString(R.string.vat_rate_required_error), Toast.LENGTH_LONG).show()
            return
        }"""
NEW_VALIDATION = """        // Update 63: sprzedawca jest już podatnikiem VAT — stawka VAT jest obowiązkowa na
        // KAŻDEJ pozycji faktury (różne pozycje mogą mieć różne stawki).
        if (compliance?.requiresVatRateSelection == true && lines.any { it.vatRate == null }) {
            Toast.makeText(this, getString(R.string.vat_rate_required_per_item_error), Toast.LENGTH_LONG).show()
            return
        }"""
str_replace_any(ACT, [OLD_VALIDATION], NEW_VALIDATION, "generateInvoice(): walidacja stawki VAT per-pozycja")

OLD_SELLER_BLOCK = """        findViewById<Button>(R.id.btn_generate).isEnabled = false
        val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity, sellerBankAccount)
        val issueDateMillis = System.currentTimeMillis()
        val vatRateForInvoice = selectedVatRate
        val isReceiptForInvoice = compliance?.allowsReceiptFlag == true &&"""
NEW_SELLER_BLOCK = """        findViewById<Button>(R.id.btn_generate).isEnabled = false
        val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity, sellerBankAccount)
        val issueDateMillis = System.currentTimeMillis()
        // Update 63: Invoice.vatRate to teraz tylko pomocniczy "podgląd" — pełne dane per-pozycja
        // są w InvoiceItem.vatRate (patrz itemsForPdf niżej). Zapisujemy wspólną stawkę TYLKO gdy
        // WSZYSTKIE pozycje mają dokładnie tę samą stawkę; przy mieszanych stawkach zostaje null.
        val vatRateStorageKeyForInvoice = lines.map { it.vatRate }.distinct().singleOrNull()
        val isReceiptForInvoice = compliance?.allowsReceiptFlag == true &&"""
str_replace_any(ACT, [OLD_SELLER_BLOCK], NEW_SELLER_BLOCK, "generateInvoice(): vatRateStorageKeyForInvoice zamiast selectedVatRate")

OLD_ITEMS_FOR_PDF = """                val itemsForPdf = lines.map {
                    InvoiceItem(
                        invoiceId = 0, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category
                    )
                }"""
NEW_ITEMS_FOR_PDF = """                val itemsForPdf = lines.map {
                    InvoiceItem(
                        invoiceId = 0, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category,
                        vatRate = it.vatRate
                    )
                }"""
str_replace_any(ACT, [OLD_ITEMS_FOR_PDF], NEW_ITEMS_FOR_PDF, "itemsForPdf: przekazanie vatRate do InvoiceItem")

OLD_GENERATE_CALL = """                        items = itemsForPdf,
                        vatRate = vatRateForInvoice,
                        isReceipt = isReceiptForInvoice
                    )
                }"""
NEW_GENERATE_CALL = """                        items = itemsForPdf,
                        // Fallback tylko dla pustych items (nigdy nie zdarza się tutaj — lines
                        // jest sprawdzone jako niepuste wyżej) — per-pozycja stawki są w items.
                        vatRate = null,
                        isReceipt = isReceiptForInvoice
                    )
                }"""
str_replace_any(ACT, [OLD_GENERATE_CALL], NEW_GENERATE_CALL, "generate(): vatRate=null (fallback niedotyczacy), per-pozycja w items")

OLD_INVOICE_INSERT_VAT = """                        vatRate = vatRateForInvoice?.storageKey,
                        isReceipt = isReceiptForInvoice"""
NEW_INVOICE_INSERT_VAT = """                        vatRate = vatRateStorageKeyForInvoice,
                        isReceipt = isReceiptForInvoice"""
str_replace_any(ACT, [OLD_INVOICE_INSERT_VAT], NEW_INVOICE_INSERT_VAT, "Invoice(): vatRateStorageKeyForInvoice zamiast vatRateForInvoice?.storageKey")

OLD_ITEMS_TO_INSERT = """                val itemsToInsert = lines.map {
                    InvoiceItem(
                        invoiceId = invoiceId, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category
                    )
                }"""
NEW_ITEMS_TO_INSERT = """                val itemsToInsert = lines.map {
                    InvoiceItem(
                        invoiceId = invoiceId, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category,
                        vatRate = it.vatRate
                    )
                }"""
str_replace_any(ACT, [OLD_ITEMS_TO_INSERT], NEW_ITEMS_TO_INSERT, "itemsToInsert: przekazanie vatRate do zapisanego InvoiceItem")

# 9) po udanym wystawieniu: usuniecie resetu starego globalnego selectedVatRate/przycisku
#    (nowy pusty wiersz sam dostanie poprawna widocznosc przez addItemRow -> refreshItemVatButtonVisibility).
OLD_RESET = """                    findViewById<LinearLayout>(R.id.ll_invoice_items).removeAllViews()
                    addItemRow()
                    selectedVatRate = null
                    findViewById<android.widget.Switch>(R.id.sw_is_receipt).isChecked = false
                    refreshVatRateButtonText()
                    findViewById<Button>(R.id.btn_generate).isEnabled = true"""
NEW_RESET = """                    findViewById<LinearLayout>(R.id.ll_invoice_items).removeAllViews()
                    addItemRow()
                    findViewById<android.widget.Switch>(R.id.sw_is_receipt).isChecked = false
                    findViewById<Button>(R.id.btn_generate).isEnabled = true"""
str_replace_any(ACT, [OLD_RESET], NEW_RESET, "reset po wystawieniu: usuniecie odwolan do selectedVatRate/refreshVatRateButtonText")

print("")
print("Wszystkie patche AddInvoiceActivity.kt zastosowane pomyslnie.")
PYEOF_ACT

echo "-> krok 4/5: ids.xml / item_invoice_line.xml / activity_add_invoice.xml / InvoiceItem.kt / AppDatabase.kt (migracja v11->v12)"
python3 << 'PYEOF_FILES2'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

# ---------------------------------------------------------------------------
# ids.xml — nowy tag na wierszu pozycji: stawka VAT TEJ pozycji.
# ---------------------------------------------------------------------------
IDS = "app/src/main/res/values/ids.xml"
OLD_IDS = """    <item name="tag_ryczalt_category" type="id"/>
    <item name="tag_product_id" type="id"/>
</resources>"""
NEW_IDS = """    <item name="tag_ryczalt_category" type="id"/>
    <item name="tag_product_id" type="id"/>
    <!-- Update 63: stawka VAT (storageKey VatRate) TEJ KONKRETNEJ pozycji faktury —
         patrz btn_item_vat_rate w item_invoice_line.xml i AddInvoiceActivity.addItemRow. -->
    <item name="tag_vat_rate" type="id"/>
</resources>"""
str_replace_any(IDS, [OLD_IDS], NEW_IDS, "ids.xml: tag_vat_rate")

# ---------------------------------------------------------------------------
# item_invoice_line.xml — przycisk stawki VAT NA TEJ POZYCJI (obok kategorii ryczaltu).
# ---------------------------------------------------------------------------
ITEM_XML = "app/src/main/res/layout/item_invoice_line.xml"
OLD_ITEM_XML = """    <Button
        android:id="@+id/btn_item_ryczalt_category"
        android:layout_width="match_parent"
        android:layout_height="44dp"
        android:background="@drawable/card_bg"
        android:text="@string/ryczalt_category_choose"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="13sp"
        android:gravity="start|center_vertical"
        android:paddingStart="14dp"
        android:paddingEnd="14dp"
        android:visibility="gone"/>

</LinearLayout>"""
NEW_ITEM_XML = """    <Button
        android:id="@+id/btn_item_ryczalt_category"
        android:layout_width="match_parent"
        android:layout_height="44dp"
        android:background="@drawable/card_bg"
        android:text="@string/ryczalt_category_choose"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="13sp"
        android:gravity="start|center_vertical"
        android:paddingStart="14dp"
        android:paddingEnd="14dp"
        android:visibility="gone"/>

    <!-- Update 63: stawka VAT TEJ KONKRETNEJ pozycji — widoczna tylko gdy sprzedawca jest
         już zarejestrowanym podatnikiem VAT (zob. AddInvoiceActivity.refreshItemVatButtonVisibility);
         różne pozycje na jednej fakturze mogą mieć różne stawki VAT. -->
    <Button
        android:id="@+id/btn_item_vat_rate"
        android:layout_width="match_parent"
        android:layout_height="44dp"
        android:layout_marginTop="8dp"
        android:background="@drawable/card_bg"
        android:text="@string/vat_rate_choose"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="13sp"
        android:gravity="start|center_vertical"
        android:paddingStart="14dp"
        android:paddingEnd="14dp"
        android:visibility="gone"/>

</LinearLayout>"""
str_replace_any(ITEM_XML, [OLD_ITEM_XML], NEW_ITEM_XML, "item_invoice_line.xml: btn_item_vat_rate")

# ---------------------------------------------------------------------------
# InvoiceItem.kt — pole vatRate (storageKey VatRate) TEJ pozycji.
# ---------------------------------------------------------------------------
ITEM_KT = "app/src/main/java/com/example/fa_ksiegowy/InvoiceItem.kt"
OLD_ITEM_KT = """    // Категория ryczałtu (см. RyczaltCategory) для этой конкретной позиции —
    // заполняется, только когда в настройках выбран ActivityType.JDG_RYCZALT
    // (см. AddInvoiceActivity), так как одна фактура может содержать и товар,
    // и услугу с разными ставками ryczałtu одновременно.
    val ryczaltCategory: String? = null
)"""
NEW_ITEM_KT = """    // Категория ryczałtu (см. RyczaltCategory) для этой конкретной позиции —
    // заполняется, только когда в настройках выбран ActivityType.JDG_RYCZALT
    // (см. AddInvoiceActivity), так как одна фактура может содержать и товар,
    // и услугу с разными ставками ryczałtu одновременно.
    val ryczaltCategory: String? = null,
    // Update 63: stawka VAT (storageKey VatRate) TEJ KONKRETNEJ pozycji — zapełniana
    // tylko gdy sprzedawca jest już zarejestrowanym podatnikiem VAT (zob.
    // VatComplianceHelper). Różne pozycje na jednej fakturze mogą mieć różne stawki
    // (towar 23%, książka 5% itd.) — dlatego stawka jest właściwością POZYCJI, a nie
    // jednego wyboru na całą fakturę (jak dawniej Invoice.vatRate).
    val vatRate: String? = null
)"""
str_replace_any(ITEM_KT, [OLD_ITEM_KT], NEW_ITEM_KT, "InvoiceItem.kt: pole vatRate")

# ---------------------------------------------------------------------------
# AppDatabase.kt — v11 -> v12, nowa kolumna invoice_items.vatRate.
# ---------------------------------------------------------------------------
DB = "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt"
OLD_DB_VERSION = """    version = 11,
    exportSchema = false
)"""
NEW_DB_VERSION = """    version = 12,
    exportSchema = false
)"""
str_replace_any(DB, [OLD_DB_VERSION], NEW_DB_VERSION, "AppDatabase.kt: version 11 -> 12")

OLD_MIGRATION_BLOCK = """        @Volatile private var INSTANCE: AppDatabase? = null
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fa_ksiegowy.db"
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }"""
NEW_MIGRATION_BLOCK = """        /** v11 -> v12: każda pozycja faktury (invoice_items) ma teraz WŁASNĄ stawkę VAT
         *  (vatRate, storageKey [VatRate]) zamiast jednej wspólnej stawki na całą fakturę
         *  (Invoice.vatRate, pozostawione bez zmian jako "podgląd" — patrz AddInvoiceActivity) —
         *  różne towary/usługi na jednej fakturze mogą być opodatkowane różnymi stawkami.
         *  Obyczajna migracja, bez utraty już zapisanych danych — dla wszystkich wcześniej
         *  zapisanych pozycji kolumna pozostaje NULL. */
        private val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoice_items ADD COLUMN vatRate TEXT")
            }
        }

        @Volatile private var INSTANCE: AppDatabase? = null
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fa_ksiegowy.db"
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }"""
str_replace_any(DB, [OLD_MIGRATION_BLOCK], NEW_MIGRATION_BLOCK, "AppDatabase.kt: MIGRATION_11_12 (invoice_items.vatRate)")

# ---------------------------------------------------------------------------
# activity_add_invoice.xml — usuniecie globalnego przycisku btn_vat_rate, w jego
# miejsce krotka podpowiedz (widoczna tylko gdy VAT obowiazuje), ze stawke wybiera
# sie teraz na kazdej pozycji ponizej.
# ---------------------------------------------------------------------------
LAYOUT = "app/src/main/res/layout/activity_add_invoice.xml"
OLD_LAYOUT_BTN = """    <!-- Stawka VAT — widoczna tylko gdy sprzedawca jest już zarejestrowanym podatnikiem VAT. -->
    <Button
        android:id="@+id/btn_vat_rate"
        android:layout_width="match_parent"
        android:layout_height="52dp"
        android:layout_marginBottom="10dp"
        android:background="@drawable/input_field_bg"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="14sp"
        android:gravity="start|center_vertical"
        android:paddingStart="16dp"
        android:paddingEnd="16dp"
        android:visibility="gone"/>"""
NEW_LAYOUT_BTN = """    <!-- Update 63: stawka VAT jest teraz wybierana OSOBNO na każdej pozycji poniżej
         (zob. item_invoice_line.xml/btn_item_vat_rate) — ta podpowiedź tylko informuje o
         tym, widoczna gdy sprzedawca jest już zarejestrowanym podatnikiem VAT. -->
    <TextView
        android:id="@+id/tv_vat_rate_info"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="10dp"
        android:text="@string/vat_rate_per_item_info"
        android:textColor="@color/text_secondary"
        android:textSize="12sp"
        android:visibility="gone"/>"""
str_replace_any(LAYOUT, [OLD_LAYOUT_BTN], NEW_LAYOUT_BTN, "activity_add_invoice.xml: usuniecie btn_vat_rate, dodanie tv_vat_rate_info")

print("")
print("Wszystkie patche (ids/layouty/DB/InvoiceItem) zastosowane pomyslnie.")
PYEOF_FILES2

echo "-> krok 5/5: strings.xml (en/pl/ru) — nowe napisy"
python3 << 'PYEOF_STRINGS'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

LOCALES = {
    "app/src/main/res/values/strings.xml": {
        "old": ('    <string name="vat_rate_required_error">Choose a VAT rate for this invoice</string>\n'
                '    <string name="vat_rate_23">23% (standard)</string>'),
        "new": ('    <string name="vat_rate_required_error">Choose a VAT rate for this invoice</string>\n'
                '    <string name="vat_rate_required_per_item_error">Choose a VAT rate for every item</string>\n'
                '    <string name="vat_rate_per_item_info">VAT is now registered — choose a VAT rate for each item below</string>\n'
                '    <string name="vat_rate_23">23% (standard)</string>'),
        "old2": ('    <string name="invoice_pdf_table_brutto">Gross value</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Invoice issued for the fiscal receipt (paragon)</string>'),
        "new2": ('    <string name="invoice_pdf_table_brutto">Gross value</string>\n'
                 '    <string name="invoice_pdf_vat_breakdown_label">Included</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Invoice issued for the fiscal receipt (paragon)</string>'),
    },
    "app/src/main/res/values-pl/strings.xml": {
        "old": ('    <string name="vat_rate_required_error">Wybierz stawkę VAT dla tej faktury</string>\n'
                '    <string name="vat_rate_23">23% (podstawowa)</string>'),
        "new": ('    <string name="vat_rate_required_error">Wybierz stawkę VAT dla tej faktury</string>\n'
                '    <string name="vat_rate_required_per_item_error">Wybierz stawkę VAT dla każdej pozycji</string>\n'
                '    <string name="vat_rate_per_item_info">Jesteś już płatnikiem VAT — wybierz stawkę VAT dla każdej pozycji poniżej</string>\n'
                '    <string name="vat_rate_23">23% (podstawowa)</string>'),
        "old2": ('    <string name="invoice_pdf_table_brutto">Wartość brutto</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Faktura wystawiona do paragonu fiskalnego</string>'),
        "new2": ('    <string name="invoice_pdf_table_brutto">Wartość brutto</string>\n'
                 '    <string name="invoice_pdf_vat_breakdown_label">W tym</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Faktura wystawiona do paragonu fiskalnego</string>'),
    },
    "app/src/main/res/values-ru/strings.xml": {
        "old": ('    <string name="vat_rate_required_error">Выберите ставку VAT для этой фактуры</string>\n'
                '    <string name="vat_rate_23">23% (базовая)</string>'),
        "new": ('    <string name="vat_rate_required_error">Выберите ставку VAT для этой фактуры</string>\n'
                '    <string name="vat_rate_required_per_item_error">Выберите ставку VAT для каждой позиции</string>\n'
                '    <string name="vat_rate_per_item_info">Вы уже плательщик VAT — выберите ставку VAT для каждой позиции ниже</string>\n'
                '    <string name="vat_rate_23">23% (базовая)</string>'),
        "old2": ('    <string name="invoice_pdf_table_brutto">Стоимость брутто</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Фактура выставлена к фискальному чеку</string>'),
        "new2": ('    <string name="invoice_pdf_table_brutto">Стоимость брутто</string>\n'
                 '    <string name="invoice_pdf_vat_breakdown_label">В т.ч.</string>\n'
                 '    <string name="invoice_pdf_receipt_label">Фактура выставлена к фискальному чеку</string>'),
    },
}

for path, spec in LOCALES.items():
    str_replace_any(path, [spec["old"]], spec["new"], "vat_rate_required_per_item_error + vat_rate_per_item_info")
    str_replace_any(path, [spec["old2"]], spec["new2"], "invoice_pdf_vat_breakdown_label")

print("")
print("Wszystkie nowe stringi (en/pl/ru) dodane pomyslnie.")
PYEOF_STRINGS

echo ""
echo "Gotowe."
echo ""
echo "Co zrobic dalej (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 63: stawka VAT na kazdej pozycji faktury (zamiast jednej na cala fakture) + tabela Netto/VAT/Brutto z blokiem W tym i Razem + naprawa DO ZAPLATY (brutto zamiast netto)\""
echo "  git push origin main"
