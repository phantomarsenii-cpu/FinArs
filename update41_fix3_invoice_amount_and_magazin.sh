#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Update 41 fix 3: сумма фактуры (запятая/точка) + подписи в форме товара ==="
echo ""
echo "Причина ошибки 'заполните данные фактуры': при выборе товаров со склада сумма"
echo "подставлялась в формате твоей локали (запятая, напр. 24,99), а при нажатии"
echo "'Сгенерировать фактуру' сумма читалась функцией, которая понимает только точку —"
echo "поэтому поле выглядело заполненным, но программа не могла прочитать число."
echo ""
echo "Плюс: в Magazyn справа от товара показывалось '5,0 1' — это количество (5) и"
echo "единица измерения (у Winston она была введена как '1', а не 'szt.') слитно без"
echo "подписей полей. Добавляю подписи над полями и убираю лишние нули в списке."
echo ""

JAVA_DIR="app/src/main/java/com/example/fa_ksiegowy"
LAYOUT_DIR="app/src/main/res/layout"

if [ ! -f "settings.gradle" ] || [ ! -f "$JAVA_DIR/AddInvoiceActivity.kt" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy (там, где settings.gradle)"
    exit 1
fi

BACKUP_DIR=".update41_fix3_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/$JAVA_DIR" "$BACKUP_DIR/$LAYOUT_DIR"
cp "$JAVA_DIR/AddInvoiceActivity.kt" "$BACKUP_DIR/$JAVA_DIR/AddInvoiceActivity.kt"
cp "$JAVA_DIR/ProductAdapter.kt" "$BACKUP_DIR/$JAVA_DIR/ProductAdapter.kt"
cp "$LAYOUT_DIR/activity_add_edit_product.xml" "$BACKUP_DIR/$LAYOUT_DIR/activity_add_edit_product.xml"
echo "--- Бэкап сохранён в $BACKUP_DIR ---"

# ---------------------------------------------------------------------------
# 1) AddInvoiceActivity.kt — сумма читается через parseAmount (запятая ИЛИ точка)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX3_INVOICE'
path = "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"
text = open(path, encoding="utf-8").read()

old_read = '        val amount = findViewById<EditText>(R.id.et_amount).text.toString().toDoubleOrNull()'
new_read = '        val amount = parseAmount(findViewById<EditText>(R.id.et_amount).text.toString())'
if old_read not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND (amount read) — возможно, уже пофикшено")
text = text.replace(old_read, new_read, 1)

old_fn = '    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)'
new_fn = (
    '    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)\n\n'
    '    /** Читает сумму из поля независимо от того, каким разделителем введены копейки —\n'
    '     *  запятой (как показывает formatMoney на pl/ru локали) или точкой (как ожидает\n'
    '     *  стандартный toDoubleOrNull). Раньше здесь было прямое .toDoubleOrNull(), из-за\n'
    '     *  чего сумма, автоподставленная из товаров склада (с запятой), не распознавалась\n'
    '     *  и появлялась ложная ошибка "заполните данные фактуры". */\n'
    '    private fun parseAmount(raw: String): Double? = raw.trim().replace(",", ".").toDoubleOrNull()'
)
if old_fn not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND (formatMoney fun) — возможно, уже пофикшено")
text = text.replace(old_fn, new_fn, 1)

open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX3_INVOICE
echo "OK: $JAVA_DIR/AddInvoiceActivity.kt"

# ---------------------------------------------------------------------------
# 2) ProductAdapter.kt — без лишних нулей и без запятой из локали (5 szt., а не 5,0 szt.)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX3_ADAPTER'
path = "app/src/main/java/com/example/fa_ksiegowy/ProductAdapter.kt"
text = open(path, encoding="utf-8").read()

old_import = 'import androidx.recyclerview.widget.RecyclerView\nimport java.util.Locale\n'
new_import = 'import androidx.recyclerview.widget.RecyclerView\n'
if old_import not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND in ProductAdapter.kt (import) — возможно, уже пофикшено")
text = text.replace(old_import, new_import, 1)

old_line = '        holder.tvQty.text = String.format(Locale.getDefault(), "%.1f %s", p.quantity, p.unit)'
new_line = '        holder.tvQty.text = "${formatQty(p.quantity)} ${p.unit}"'
if old_line not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND in ProductAdapter.kt (tvQty line) — возможно, уже пофикшено")
text = text.replace(old_line, new_line, 1)

old_end = '    override fun getItemCount(): Int = items.size\n}'
new_end = (
    '    override fun getItemCount(): Int = items.size\n\n'
    '    /** Без лишних ".0" для целых количеств (5 szt., а не 5,0 szt.). */\n'
    '    private fun formatQty(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()\n'
    '}'
)
if old_end not in text:
    raise SystemExit("ANCHOR 3 NOT FOUND in ProductAdapter.kt (end of class) — возможно, уже пофикшено")
text = text.replace(old_end, new_end, 1)

open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX3_ADAPTER
echo "OK: $JAVA_DIR/ProductAdapter.kt"

# ---------------------------------------------------------------------------
# 3) activity_add_edit_product.xml — явные подписи над полями "Количество" и "Единица"
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX3_LAYOUT'
path = "app/src/main/res/layout/activity_add_edit_product.xml"
text = open(path, encoding="utf-8").read()

anchor = '''    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="14dp" android:weightSum="2" android:baselineAligned="false">
        <EditText android:id="@+id/et_quantity" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginEnd="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_quantity" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>
        <EditText android:id="@+id/et_unit" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_unit" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>
    </LinearLayout>'''

addition = '''    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:layout_marginEnd="8dp" android:text="@string/product_quantity" android:textColor="@color/text_secondary" android:textSize="12sp"/>
        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:layout_marginStart="8dp" android:text="@string/product_unit" android:textColor="@color/text_secondary" android:textSize="12sp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginTop="4dp" android:layout_marginBottom="14dp" android:weightSum="2" android:baselineAligned="false">
        <EditText android:id="@+id/et_quantity" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginEnd="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_quantity" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>
        <EditText android:id="@+id/et_unit" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_unit" android:text="szt." android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>
    </LinearLayout>'''

if anchor not in text:
    raise SystemExit("ANCHOR NOT FOUND in activity_add_edit_product.xml — возможно, уже пофикшено")
text = text.replace(anchor, addition, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX3_LAYOUT
echo "OK: $LAYOUT_DIR/activity_add_edit_product.xml (подписи над полями + 'szt.' по умолчанию в поле единицы)"

echo ""
echo "=== Готово. Дальше: ==="
echo "git add -A && git commit -m 'fix: invoice amount parsing (comma/dot), clearer magazyn quantity/unit fields' && git push"
echo ""
echo "ВАЖНО: у товара 'Winston' в складе единица измерения уже сохранена как '1' —"
echo "это старые данные, скрипт их не трогает. Открой Magazyn -> Winston -> исправь"
echo "поле 'Jednostka' на 'szt.' вручную и сохрани."
