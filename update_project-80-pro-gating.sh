#!/usr/bin/env bash
# Update 80: больше функций под Pro + бесплатный потолок записей + актуальные тексты про Pro.
# ОДИН скрипт (заменяет черновые 80 и 81).
#
# ОГРАНИЧЕНИЯ
#  1) ProGate.kt — единый хелпер. Любая Pro-кнопка остаётся ВИДНОЙ; при нажатии всплывает диалог
#     "🔒 Функция Pro" с кнопкой "Разблокировать Pro", которая открывает экран подписки.
#  2) Magazyn — вкладка остаётся, но поверх рисуется экран с замком (пока нет Pro).
#  3) Ewidencja sprzedaży PDF — только Pro.
#  4) Kontrahenci (выбор из списка / сохранение) — только Pro.
#  5) Записи cykliczne — переключатель в AddEntryActivity + RecurringEntryWorker только для Pro.
#  6) Уведомления: предупреждения о ЛИМИТАХ (квартальный лимит, порог 120 000 zł, VAT, kasa) остаются
#     БЕСПЛАТНЫМИ для всех. Под Pro — напоминания об авансах и сроке PIT; низкий остаток склада (Stock).
#  7) Бесплатный потолок: 30 приходов и 30 расходов в месяц (считаются отдельно, ручные записи).
#  8) Уже существующие Pro-кнопки (фактуры, PIT-36, бэкап, годовой/произвольный отчёты) переведены
#     на тот же единый диалог.
# ТЕКСТЫ
#  9) Экран подписки: 8 преимуществ (paywall_feature_1..8).
# 10) "О приложении", диалог Pro, подсказки тура — обновлены (en / pl / ru / uk).
# Запускать из КОРНЯ репозитория, ДО git add/commit/push. Скрипт идемпотентный.
set -euo pipefail

J=app/src/main/java/com/example/fa_ksiegowy
R=app/src/main/res
for f in "$J/AddEntryActivity.kt" "$J/MagazinFragment.kt" "$J/ReportFragment.kt" \
         "$J/EntryDao.kt" "$J/RecurringEntryWorker.kt" "$J/StockNotificationWorker.kt" \
         "$J/LimitsNotificationWorker.kt" "$J/AddInvoiceActivity.kt" "$J/MineFragment.kt" \
         "$J/SettingsFragment.kt" "$R/layout/activity_settings_pro.xml" \
         "$R/values/strings.xml" "$R/values-pl/strings.xml" "$R/values-ru/strings.xml" "$R/values-uk/strings.xml"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

python3 - <<'PY'
import re
J = "app/src/main/java/com/example/fa_ksiegowy"
R = "app/src/main/res"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s):
    open(p, "w", encoding="utf-8").write(s)
    print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден (или не уникален) фрагмент: " + what
    return s.replace(old, new)

# ---------------------------------------------------------------- ProGate.kt
p = J + "/ProGate.kt"
try:
    open(p, encoding="utf-8").close()
    print("ProGate.kt: уже есть")
except FileNotFoundError:
    write(p, '''package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Update 80: единое место для Pro-ограничений. Раньше диалог "функция Pro" был
 * скопирован в нескольких экранах (и в одном из них проверку просто забыли).
 */
object ProGate {

    /** Бесплатный потолок: приходов и расходов В МЕСЯЦ (каждый тип считается отдельно). */
    const val FREE_ENTRIES_PER_MONTH = 30

    fun isPro(context: Context): Boolean = BillingManager.isPro(context)

    /** Выполняет action, если Pro активен; иначе показывает диалог с переходом на экран подписки. */
    fun require(context: Context, messageRes: Int, action: () -> Unit) {
        if (isPro(context)) action() else showLockedDialog(context, messageRes)
    }

    /** Экран подписки (в меню: Настройки -> Pro версия). */
    fun openPaywall(context: Context) {
        val i = Intent(context, SettingsProActivity::class.java)
        if (context !is Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(i)
    }

    fun showLockedDialog(context: Context, messageRes: Int) {
        AppDialog.show(
            context = context,
            title = "🔒 " + context.getString(R.string.pro_feature_locked_title),
            message = context.getString(messageRes),
            positiveText = context.getString(R.string.pro_unlock_button),
            onPositive = { openPaywall(context) },
            negativeText = context.getString(R.string.dialog_close)
        )
    }

    /**
     * true, если без Pro в календарном месяце даты [dateMillis] уже набрано
     * FREE_ENTRIES_PER_MONTH ручных записей данного типа. Вызывать с фонового потока.
     * Записи, созданные фактурами/корректами, в потолок не входят.
     */
    suspend fun freeLimitReached(context: Context, isIncome: Boolean, dateMillis: Long): Boolean {
        if (isPro(context)) return false
        val cal = Calendar.getInstance().apply {
            timeInMillis = dateMillis
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val from = cal.timeInMillis
        cal.add(Calendar.MONTH, 1)
        val to = cal.timeInMillis - 1
        val count = AppDatabase.getInstance(context.applicationContext)
            .entryDao().countManualBetween(isIncome, from, to)
        return count >= FREE_ENTRIES_PER_MONTH
    }
}
''')

# ---------------------------------------------------------------- EntryDao.kt
p = J + "/EntryDao.kt"
s = read(p)
if "countManualBetween" in s:
    print("EntryDao: уже применено")
else:
    s = rep(s,
        "    /** Полная очистка истории",
        "    /** Update 80: сколько записей данного типа создано ВРУЧНУЮ за период — для бесплатного\n"
        "     *  потолка (см. ProGate.freeLimitReached). Записи от фактур/корект не считаются. */\n"
        "    @Query(\"SELECT COUNT(*) FROM entries WHERE isIncome = :isIncome AND invoiceId IS NULL AND invoiceCorrectionId IS NULL AND dateMillis BETWEEN :from AND :to\")\n"
        "    suspend fun countManualBetween(isIncome: Boolean, from: Long, to: Long): Int\n\n"
        "    /** Полная очистка истории",
        "EntryDao anchor")
    write(p, s)

# ---------------------------------------------------------------- AddEntryActivity.kt
p = J + "/AddEntryActivity.kt"
s = read(p)
if "Update 80" in s:
    print("AddEntryActivity: уже применено")
else:
    s = rep(s,
        "        findViewById<android.widget.Switch>(R.id.sw_recurring).setOnCheckedChangeListener { _, checked ->\n"
        "            wantsRecurring = checked\n"
        "        }\n",
        "        // Update 80: повторяющиеся записи — только Pro.\n"
        "        findViewById<android.widget.Switch>(R.id.sw_recurring).setOnCheckedChangeListener { btn, checked ->\n"
        "            if (checked && !BillingManager.isPro(this)) {\n"
        "                btn.isChecked = false\n"
        "                ProGate.showLockedDialog(this, R.string.recurring_pro_locked_message)\n"
        "                return@setOnCheckedChangeListener\n"
        "            }\n"
        "            wantsRecurring = checked\n"
        "        }\n",
        "recurring switch")
    s = rep(s,
        "                val dao = AppDatabase.getInstance(applicationContext).entryDao()\n"
        "                val finalReceiptPath = renameReceiptToStandardName(\n",
        "                val dao = AppDatabase.getInstance(applicationContext).entryDao()\n"
        "                // Update 80: бесплатный потолок — 30 приходов и 30 расходов в месяц.\n"
        "                // Проверяем только новые записи (и смену типа при редактировании).\n"
        "                if ((existing == null || existing.isIncome != currentIsIncome) &&\n"
        "                    ProGate.freeLimitReached(applicationContext, currentIsIncome, selectedDateMillis)) {\n"
        "                    withContext(Dispatchers.Main) {\n"
        "                        findViewById<Button>(R.id.btn_save).isEnabled = true\n"
        "                        ProGate.showLockedDialog(\n"
        "                            this@AddEntryActivity,\n"
        "                            if (currentIsIncome) R.string.free_limit_income_message else R.string.free_limit_expense_message\n"
        "                        )\n"
        "                    }\n"
        "                    return@launch\n"
        "                }\n"
        "                val finalReceiptPath = renameReceiptToStandardName(\n",
        "save flow")
    write(p, s)

# ---------------------------------------------------------------- ReportFragment.kt (Ewidencja)
p = J + "/ReportFragment.kt"
s = read(p)
if "ewidencja_pro_locked_message" in s:
    print("ReportFragment: уже применено")
else:
    s = rep(s,
        "requireView().findViewById<Button>(R.id.btn_report_ewidencja).setOnClickListener { showEwidencjaPeriodPicker() }",
        "requireView().findViewById<Button>(R.id.btn_report_ewidencja).setOnClickListener {\n"
        "            // Update 80: Ewidencja sprzedaży PDF — только Pro.\n"
        "            ProGate.require(requireContext(), R.string.ewidencja_pro_locked_message) { showEwidencjaPeriodPicker() }\n"
        "        }",
        "ewidencja button")
    write(p, s)

# ---------------------------------------------------------------- AddInvoiceActivity.kt (kontrahenci)
p = J + "/AddInvoiceActivity.kt"
s = read(p)
if "contractors_pro_locked_message" in s:
    print("AddInvoiceActivity: уже применено")
else:
    s = rep(s,
        "        findViewById<Button>(R.id.btn_select_contractor).setOnClickListener {\n"
        "            selectContractorLauncher.launch(Intent(this, SelectContractorActivity::class.java))\n"
        "        }\n"
        "        findViewById<Button>(R.id.btn_save_contractor).setOnClickListener { confirmSaveContractor() }\n",
        "        // Update 80: список контрагентов и их сохранение — только Pro (страховка: сам экран\n"
        "        // фактур уже доступен только с Pro).\n"
        "        findViewById<Button>(R.id.btn_select_contractor).setOnClickListener {\n"
        "            ProGate.require(this, R.string.contractors_pro_locked_message) {\n"
        "                selectContractorLauncher.launch(Intent(this, SelectContractorActivity::class.java))\n"
        "            }\n"
        "        }\n"
        "        findViewById<Button>(R.id.btn_save_contractor).setOnClickListener {\n"
        "            ProGate.require(this, R.string.contractors_pro_locked_message) { confirmSaveContractor() }\n"
        "        }\n",
        "contractor buttons")
    write(p, s)

# ---------------------------------------------------------------- Workers
p = J + "/RecurringEntryWorker.kt"
s = read(p)
if "Update 80" in s:
    print("RecurringEntryWorker: уже применено")
else:
    s = rep(s,
        "    override suspend fun doWork(): Result {\n        return try {\n",
        "    override suspend fun doWork(): Result {\n"
        "        // Update 80: автозапись повторяющихся операций — только Pro.\n"
        "        if (!BillingManager.isPro(applicationContext)) return Result.success()\n"
        "        return try {\n",
        "RecurringEntryWorker.doWork")
    write(p, s)

p = J + "/StockNotificationWorker.kt"
s = read(p)
if "Update 80" in s:
    print("StockNotificationWorker: уже применено")
else:
    s = rep(s,
        "    override suspend fun doWork(): Result {\n        return try {\n",
        "    override suspend fun doWork(): Result {\n"
        "        // Update 80: уведомления о низком остатке — только Pro (склад целиком под Pro).\n"
        "        if (!BillingManager.isPro(applicationContext)) return Result.success()\n"
        "        return try {\n",
        "StockNotificationWorker.doWork")
    write(p, s)

p = J + "/LimitsNotificationWorker.kt"
s = read(p)
if "Update 80" in s:
    print("LimitsNotificationWorker: уже применено")
else:
    # Предупреждения о ЛИМИТАХ (квартальный лимит, порог 120 000 zł, VAT, kasa fiskalna) остаются
    # бесплатными для всех. Под Pro — только напоминания об авансах и о сроке подачи PIT.
    s = rep(s,
        "            val prefs = applicationContext.getSharedPreferences(\"settings\", Context.MODE_PRIVATE)\n"
        "            val today = SDF_DAY.format(java.util.Date())\n",
        "            val prefs = applicationContext.getSharedPreferences(\"settings\", Context.MODE_PRIVATE)\n"
        "            val today = SDF_DAY.format(java.util.Date())\n"
        "            // Update 80: напоминания об авансах и о сроке PIT — только Pro; все предупреждения\n"
        "            // о лимитах остаются бесплатными.\n"
        "            val isPro = BillingManager.isPro(applicationContext)\n",
        "Limits: isPro")
    s = rep(s,
        "            if (limits.activityType.isRegisteredJdg && day in 15..20) {\n",
        "            if (isPro && limits.activityType.isRegisteredJdg && day in 15..20) {\n",
        "Limits: advance")
    s = rep(s,
        "            if (month == Calendar.FEBRUARY || month == Calendar.MARCH ||\n"
        "                (month == Calendar.APRIL && day <= 30)\n"
        "            ) {\n",
        "            if (isPro && (month == Calendar.FEBRUARY || month == Calendar.MARCH ||\n"
        "                (month == Calendar.APRIL && day <= 30))\n"
        "            ) {\n",
        "Limits: PIT")
    write(p, s)

# ---------------------------------------------------------------- Magazyn: экран с замком
lay = R + "/layout/view_magazin_locked.xml"
try:
    open(lay, encoding="utf-8").close()
    print("view_magazin_locked.xml: уже есть")
except FileNotFoundError:
    write(lay, '''<?xml version="1.0" encoding="utf-8"?>
<!-- Update 80: заглушка поверх вкладки Magazyn, пока нет Pro. -->
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bg_top"
    android:clickable="true"
    android:focusable="true">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:gravity="center_horizontal"
        android:orientation="vertical"
        android:paddingStart="32dp"
        android:paddingEnd="32dp"
        android:paddingBottom="120dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="&#128274;"
            android:textSize="56sp"
            android:layout_marginBottom="16dp"/>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/magazin_locked_title"
            android:textColor="@color/text_primary"
            android:textSize="20sp"
            android:textStyle="bold"
            android:layout_marginBottom="10dp"/>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/magazin_locked_message"
            android:textColor="@color/text_secondary"
            android:textSize="14sp"
            android:layout_marginBottom="24dp"/>

        <Button
            android:id="@+id/btn_magazin_locked_try"
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/magazin_locked_button"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"/>
    </LinearLayout>
</FrameLayout>
''')

p = J + "/MagazinFragment.kt"
s = read(p)
if "Update 80" in s:
    print("MagazinFragment: уже применено")
else:
    s = rep(s,
        "    private lateinit var adapter: ProductAdapter\n",
        "    private lateinit var adapter: ProductAdapter\n"
        "    // Update 80: заглушка с замком поверх экрана склада (видна, пока нет Pro).\n"
        "    private var lockOverlay: View? = null\n",
        "adapter field")
    s = rep(s,
        "        requireView().findViewById<Button>(R.id.btn_inventory).setOnClickListener {\n"
        "            startActivity(Intent(requireContext(), InventoryActivity::class.java))\n"
        "        }\n"
        "    }\n",
        "        requireView().findViewById<Button>(R.id.btn_inventory).setOnClickListener {\n"
        "            startActivity(Intent(requireContext(), InventoryActivity::class.java))\n"
        "        }\n"
        "\n"
        "        // Update 80: Magazyn закрыт целиком под Pro — вкладку не прячем, а закрываем\n"
        "        // экраном с замком (корень fragment_magazin — FrameLayout, оверлей ложится сверху).\n"
        "        val root = view as ViewGroup\n"
        "        val overlay = layoutInflater.inflate(R.layout.view_magazin_locked, root, false)\n"
        "        overlay.findViewById<Button>(R.id.btn_magazin_locked_try).setOnClickListener {\n"
        "            ProGate.openPaywall(requireContext())\n"
        "        }\n"
        "        root.addView(overlay)\n"
        "        lockOverlay = overlay\n"
        "        updateLockOverlay()\n"
        "    }\n"
        "\n"
        "    /** Показывает/скрывает замок — вызывается и при возврате с экрана подписки. */\n"
        "    private fun updateLockOverlay() {\n"
        "        lockOverlay?.visibility = if (BillingManager.isPro(requireContext())) View.GONE else View.VISIBLE\n"
        "    }\n",
        "onViewCreated end")
    s = rep(s,
        "    override fun onResume() {\n        super.onResume()\n        loadProducts()\n    }\n",
        "    override fun onResume() {\n        super.onResume()\n        updateLockOverlay()\n        loadProducts()\n    }\n",
        "onResume")
    s = rep(s,
        "    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {\n        super.onViewCreated(view, savedInstanceState)\n",
        "    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {\n        super.onViewCreated(view, savedInstanceState)\n        lockOverlay = null\n",
        "onViewCreated head")
    write(p, s)

# ---------------------------------------------------------------- Строки
STR = {
 "values": {
  "free_limit_income_message": "You have reached the free limit of 30 income entries per month. Unlock Pro to add more.",
  "free_limit_expense_message": "You have reached the free limit of 30 expense entries per month. Unlock Pro to add more.",
  "recurring_pro_locked_message": "Recurring entries are a Pro feature. Unlock Pro to use them.",
  "ewidencja_pro_locked_message": "The sales register (Ewidencja) PDF is a Pro feature. Unlock Pro to generate it.",
  "contractors_pro_locked_message": "Saved contractors are a Pro feature. Unlock Pro to use them.",
  "magazin_locked_title": "Warehouse is a Pro feature",
  "magazin_locked_message": "Stock levels, barcode scanning, inventory counts and low-stock alerts are available with Pro. Start your free trial.",
  "magazin_locked_button": "Try Pro",
 },
 "values-pl": {
  "free_limit_income_message": "Osiągnięto bezpłatny limit: 30 przychodów miesięcznie. Odblokuj Pro, aby dodawać więcej.",
  "free_limit_expense_message": "Osiągnięto bezpłatny limit: 30 wydatków miesięcznie. Odblokuj Pro, aby dodawać więcej.",
  "recurring_pro_locked_message": "Wpisy cykliczne to funkcja Pro. Odblokuj Pro, aby z nich korzystać.",
  "ewidencja_pro_locked_message": "Ewidencja sprzedaży w PDF to funkcja Pro. Odblokuj Pro, aby ją wygenerować.",
  "contractors_pro_locked_message": "Zapisani kontrahenci to funkcja Pro. Odblokuj Pro, aby z nich korzystać.",
  "magazin_locked_title": "Magazyn to funkcja Pro",
  "magazin_locked_message": "Stany magazynowe, skanowanie kodów kreskowych, inwentaryzacja i powiadomienia o niskim stanie są dostępne w wersji Pro. Rozpocznij bezpłatny okres próbny.",
  "magazin_locked_button": "Wypróbuj Pro",
 },
 "values-ru": {
  "free_limit_income_message": "Достигнут бесплатный лимит: 30 приходов в месяц. Разблокируйте Pro, чтобы добавлять больше.",
  "free_limit_expense_message": "Достигнут бесплатный лимит: 30 расходов в месяц. Разблокируйте Pro, чтобы добавлять больше.",
  "recurring_pro_locked_message": "Повторяющиеся записи — функция Pro. Разблокируйте Pro, чтобы ими пользоваться.",
  "ewidencja_pro_locked_message": "Ewidencja sprzedaży в PDF — функция Pro. Разблокируйте Pro, чтобы её сформировать.",
  "contractors_pro_locked_message": "Сохранённые контрагенты — функция Pro. Разблокируйте Pro, чтобы ими пользоваться.",
  "magazin_locked_title": "Склад — функция Pro",
  "magazin_locked_message": "Остатки товаров, сканирование штрихкодов, инвентаризация и уведомления о низком остатке доступны в Pro. Начните бесплатный пробный период.",
  "magazin_locked_button": "Попробовать Pro",
 },
 "values-uk": {
  "free_limit_income_message": "Досягнуто безкоштовний ліміт: 30 доходів на місяць. Розблокуйте Pro, щоб додавати більше.",
  "free_limit_expense_message": "Досягнуто безкоштовний ліміт: 30 витрат на місяць. Розблокуйте Pro, щоб додавати більше.",
  "recurring_pro_locked_message": "Регулярні записи — це функція Pro. Розблокуйте Pro, щоб їх використовувати.",
  "ewidencja_pro_locked_message": "Ewidencja sprzedaży у PDF — це функція Pro. Розблокуйте Pro, щоб її сформувати.",
  "contractors_pro_locked_message": "Збережені контрагенти — це функція Pro. Розблокуйте Pro, щоб їх використовувати.",
  "magazin_locked_title": "Склад — це функція Pro",
  "magazin_locked_message": "Залишки товарів, сканування штрихкодів, інвентаризація та сповіщення про низький залишок доступні в Pro. Почніть безкоштовний пробний період.",
  "magazin_locked_button": "Спробувати Pro",
 },
}
for folder, items in STR.items():
    p = R + "/" + folder + "/strings.xml"
    s = read(p)
    if 'name="free_limit_income_message"' in s:
        print(folder + "/strings.xml: уже применено")
        continue
    block = "    <!-- Update 80: Pro-ограничения -->\n"
    for k, v in items.items():
        assert "'" not in v and "%" not in v and "&" not in v and "<" not in v, k
        block += '    <string name="%s">%s</string>\n' % (k, v)
    s = rep(s, "</resources>", block + "</resources>", folder + " </resources>")
    write(p, s)


# ==================== ТЕКСТЫ ====================
import re
R = "app/src/main/res"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s):
    open(p, "w", encoding="utf-8").write(s)
    print("изменён:", p)

def set_string(s, name, value):
    pat = re.compile(r'(<string name="%s">)(.*?)(</string>)' % re.escape(name), re.S)
    assert len(pat.findall(s)) == 1, "строка не найдена или не уникальна: " + name
    return pat.sub(lambda m: m.group(1) + value + m.group(3), s)

def set_array(s, name, items):
    pat = re.compile(r'<string-array name="%s">.*?</string-array>' % re.escape(name), re.S)
    assert len(pat.findall(s)) == 1, "массив не найден: " + name
    body = '<string-array name="%s">\n' % name + "".join("        <item>%s</item>\n" % i for i in items) + "    </string-array>"
    return pat.sub(lambda m: body, s)

def info(head, items):
    return head + "\\n\\n" + "\\n".join("\\u2022 " + i for i in items)

# ------------------------------------------------------------------ тексты
L = {}

L["values"] = dict(
 paywall_feature_1="Unlimited income and expense entries",
 paywall_feature_2="Warehouse: barcode scanner, stock and inventory",
 paywall_feature_3="Invoices and receipts (PDF), saved contractors",
 paywall_feature_4="PIT-36 return and sales register (Ewidencja) PDF",
 paywall_feature_5="Yearly and custom-period Excel reports",
 paywall_feature_6="Recurring entries and PIT / advance reminders",
 paywall_feature_7="Data backup and restore",
 paywall_feature_8="No ads",
 pro_status_locked="Pro is locked. Unlock to remove the monthly entry limit and get warehouse, invoices, reports, backup and more.",
 pro_info_message=info("Pro unlocks:", [
    "Unlimited income and expense entries (free plan: 30 + 30 per month)",
    "Warehouse: barcode scanning, stock, inventory, low-stock alerts",
    "Invoices and receipts (PDF), saved contractors",
    "PIT-36 return and sales register (Ewidencja) PDF",
    "Yearly and custom-period Excel reports",
    "Recurring entries, PIT deadline and advance-payment reminders",
    "Backup &amp; restore",
    "No ads"]),
 tour_pro_text="Pro removes the monthly entry limit and unlocks warehouse, invoices (PDF), saved contractors, PIT-36 and sales register PDFs, yearly and custom-period Excel reports, recurring entries, PIT deadline and advance-payment reminders, backup and restore, and removes ads. It starts with a 7-day free trial.",
 tour_bell_text="Reminders about limits, low stock, invoice due dates and the annual PIT deadline appear here. Limit warnings are free; low-stock and PIT reminders need Pro.",
 tour_add_text="Tap + to add income or an expense: amount, date, category, comment and an attachment such as a receipt photo. You can also make an entry recurring (Pro). Free plan: up to 30 income and 30 expense entries per month.",
 tour_magazin_text="Manage products and stock: add items by hand or with the barcode scanner, run an inventory count and get low-stock alerts. Warehouse is a Pro feature.",
 tour_reports_text="Pick a period to see how income, expenses and tax are split. The monthly report exports to Excel for free; yearly and custom reports and the sales register (Ewidencja) PDF are Pro.",
 about_subscription_note="⭐ Free plan: up to 30 income and 30 expense entries per month, monthly report, limit tracking and warnings, PIN lock. Pro subscription: monthly or yearly plan, 7 days free trial, cancel anytime.",
 about_section_warehouse_title="📦 Warehouse (Pro)",
)
L["values"]["_arrays"] = dict(
 about_bullets_finance=[
    "Income and expense tracking with attached receipts and colour-coded categories",
    "Free plan: up to 30 income and 30 expense entries per month — Pro removes the limit",
    "Automatic profit and tax calculation (12%/32% scale)",
    "Recurring transactions (rent, subscriptions) created automatically every month (Pro)",
    "Unregistered-activity limit tracking (120,000 zł threshold)",
    "Warnings about approaching and exceeded limits (free); PIT deadline and advance-payment reminders (Pro)"],
 about_bullets_invoices=[
    "Issue invoices/receipts to individuals with PDF generation",
    "Saved contractors — pick a buyer from the list in one tap",
    "Statuses: Paid / Pending / Overdue, plus due-date reminders",
    "Tracking of the annual 20,000 zł cash-sales limit for private individuals",
    "Invoice history with search and filters"],
 about_bullets_reports=[
    "Income/expense summary and 6-month trend chart",
    "Export monthly report (free), yearly and custom-period reports (Pro) to Excel with receipts",
    "Sales register (Ewidencja sprzedaży) in PDF for a month, quarter, year or custom period (Pro)",
    "Generate PIT-36 tax returns — helper PDF and official form filling (Pro)"],
)

L["values-pl"] = dict(
 paywall_feature_1="Bez limitu przychodów i wydatków",
 paywall_feature_2="Magazyn: skaner kodów kreskowych, stany i inwentaryzacja",
 paywall_feature_3="Faktury i rachunki (PDF), zapisani kontrahenci",
 paywall_feature_4="Deklaracja PIT-36 i ewidencja sprzedaży (PDF)",
 paywall_feature_5="Raporty roczne i za dowolny okres (Excel)",
 paywall_feature_6="Wpisy cykliczne i przypomnienia o PIT i zaliczkach",
 paywall_feature_7="Kopia zapasowa i przywracanie danych",
 paywall_feature_8="Brak reklam",
 pro_status_locked="Pro jest zablokowane. Odblokuj, aby znieść miesięczny limit wpisów i uzyskać magazyn, faktury, raporty, kopię zapasową i więcej.",
 pro_info_message=info("Pro odblokowuje:", [
    "Bez limitu przychodów i wydatków (plan bezpłatny: 30 + 30 miesięcznie)",
    "Magazyn: skanowanie kodów kreskowych, stany, inwentaryzacja, alerty o niskim stanie",
    "Faktury i rachunki (PDF), zapisani kontrahenci",
    "Deklaracja PIT-36 i ewidencja sprzedaży (PDF)",
    "Raporty roczne i za dowolny okres (Excel)",
    "Wpisy cykliczne, przypomnienia o terminie PIT i zaliczkach",
    "Kopia zapasowa i przywracanie danych",
    "Brak reklam"]),
 tour_pro_text="Pro znosi miesięczny limit wpisów i odblokowuje magazyn, faktury (PDF), zapisanych kontrahentów, PIT-36 i ewidencję sprzedaży w PDF, raporty roczne i za dowolny okres w Excelu, wpisy cykliczne, przypomnienia o terminie PIT i zaliczkach, kopię zapasową i przywracanie oraz usuwa reklamy. Na start jest 7 dni za darmo.",
 tour_bell_text="Tu pojawiają się przypomnienia o limitach, niskim stanie magazynu, terminach faktur i rocznym terminie PIT. Ostrzeżenia o limitach są bezpłatne; alerty o niskim stanie i przypomnienia o PIT wymagają Pro.",
 tour_add_text="Dotknij +, aby dodać przychód lub wydatek: kwota, data, kategoria, komentarz i załącznik, np. zdjęcie paragonu. Wpis możesz też ustawić jako cykliczny (Pro). Plan bezpłatny: do 30 przychodów i 30 wydatków miesięcznie.",
 tour_magazin_text="Zarządzaj produktami i stanami: dodawaj pozycje ręcznie lub skanerem kodów kreskowych, przeprowadzaj inwentaryzację i otrzymuj alerty o niskim stanie. Magazyn to funkcja Pro.",
 tour_reports_text="Wybierz okres, aby zobaczyć podział przychodów, wydatków i podatku. Raport miesięczny eksportujesz do Excela bezpłatnie; raporty roczne i za dowolny okres oraz ewidencja sprzedaży w PDF to Pro.",
 about_subscription_note="⭐ Plan bezpłatny: do 30 przychodów i 30 wydatków miesięcznie, raport miesięczny, kontrola limitu i ostrzeżenia, blokada PIN. Subskrypcja Pro: plan miesięczny lub roczny, 7 dni za darmo, anulowanie w każdej chwili.",
 about_section_warehouse_title="📦 Magazyn (Pro)",
)
L["values-pl"]["_arrays"] = dict(
 about_bullets_finance=[
    "Ewidencja przychodów i wydatków z załącznikami paragonów i kolorowymi kategoriami",
    "Plan bezpłatny: do 30 przychodów i 30 wydatków miesięcznie — Pro znosi limit",
    "Automatyczne obliczanie zysku i podatku (skala 12%/32%)",
    "Transakcje cykliczne (czynsz, abonamenty) tworzone automatycznie co miesiąc (Pro)",
    "Kontrola limitu działalności nierejestrowanej (próg 120 000 zł)",
    "Ostrzeżenia o zbliżających się i przekroczonych limitach (bezpłatnie); przypomnienia o terminie PIT i zaliczkach (Pro)"],
 about_bullets_invoices=[
    "Wystawianie faktur/rachunków dla osób fizycznych z generowaniem PDF",
    "Zapisani kontrahenci — wybór nabywcy z listy jednym dotknięciem",
    "Statusy: Zapłacona / Oczekuje na zapłatę / Zaległa, plus przypomnienia o terminie płatności",
    "Kontrola rocznego limitu gotówki (20 000 zł) dla sprzedaży osobom fizycznym",
    "Historia faktur z wyszukiwaniem i filtrami"],
 about_bullets_reports=[
    "Podsumowanie przychodów/wydatków i wykres trendu za 6 miesięcy",
    "Eksport raportu miesięcznego (bezpłatnie), rocznego i za dowolny okres (Pro) do Excela wraz z paragonami",
    "Ewidencja sprzedaży w PDF za miesiąc, kwartał, rok lub dowolny okres (Pro)",
    "Generowanie deklaracji PIT-36 — pomocniczy PDF oraz wypełnienie oficjalnego formularza (Pro)"],
)

L["values-ru"] = dict(
 paywall_feature_1="Без лимита на доходы и расходы",
 paywall_feature_2="Склад: сканер штрихкодов, остатки и инвентаризация",
 paywall_feature_3="Счета и фактуры (PDF), сохранённые контрагенты",
 paywall_feature_4="Декларация PIT-36 и Ewidencja sprzedaży (PDF)",
 paywall_feature_5="Годовые и произвольные отчёты Excel",
 paywall_feature_6="Повторяющиеся записи и напоминания о PIT и авансах",
 paywall_feature_7="Резервная копия и восстановление данных",
 paywall_feature_8="Без рекламы",
 pro_status_locked="Pro не активирован. Разблокируйте, чтобы снять месячный лимит записей и получить склад, счета, отчёты, резервное копирование и многое другое.",
 pro_info_message=info("Pro открывает:", [
    "Без лимита на доходы и расходы (бесплатный план: 30 + 30 в месяц)",
    "Склад: сканирование штрихкодов, остатки, инвентаризация, уведомления о низком остатке",
    "Счета и фактуры (PDF), сохранённые контрагенты",
    "Декларация PIT-36 и Ewidencja sprzedaży (PDF)",
    "Годовые и произвольные отчёты в Excel",
    "Повторяющиеся записи, напоминания о сроке PIT и авансах",
    "Резервное копирование и восстановление",
    "Без рекламы"]),
 tour_pro_text="Pro снимает месячный лимит записей и открывает склад, счета и фактуры (PDF), сохранённых контрагентов, PIT-36 и Ewidencja sprzedaży в PDF, годовой и произвольный отчёты в Excel, повторяющиеся записи, напоминания о сроке PIT и авансах, резервное копирование и восстановление, а также убирает рекламу. Начинается с 7 дней бесплатно.",
 tour_bell_text="Здесь появляются напоминания о лимитах, низком остатке, сроках счетов и годовом сроке PIT. Предупреждения о лимитах бесплатны; уведомления об остатках и напоминания о PIT — в Pro.",
 tour_add_text="Нажмите +, чтобы добавить доход или расход: сумма, дата, категория, комментарий и вложение, например фото чека. Запись можно сделать повторяющейся (Pro). Бесплатный план: до 30 приходов и 30 расходов в месяц.",
 tour_magazin_text="Управляйте товарами и остатками: добавляйте позиции вручную или сканером штрихкодов, проводите инвентаризацию и получайте уведомления о низком остатке. Склад — функция Pro.",
 tour_reports_text="Выберите период, чтобы увидеть структуру доходов, расходов и налога. Месячный отчёт экспортируется в Excel бесплатно; годовой и произвольный отчёты и Ewidencja sprzedaży в PDF — Pro.",
 about_subscription_note="⭐ Бесплатный план: до 30 приходов и 30 расходов в месяц, месячный отчёт, контроль лимита и предупреждения, PIN-блокировка. Подписка Pro: месячный или годовой план, 7 дней бесплатно, отмена в любой момент.",
 about_section_warehouse_title="📦 Склад (Pro)",
)
L["values-ru"]["_arrays"] = dict(
 about_bullets_finance=[
    "Учёт доходов и расходов с чеками и цветными категориями",
    "Бесплатный план: до 30 приходов и 30 расходов в месяц — Pro снимает ограничение",
    "Автоматический расчёт прибыли и налога (шкала 12%/32%)",
    "Повторяющиеся операции (аренда, подписки) создаются автоматически каждый месяц (Pro)",
    "Контроль лимита незарегистрированной деятельности (порог 120 000 zł)",
    "Предупреждения о приближении и превышении лимитов (бесплатно); напоминания о сроке PIT и авансах (Pro)"],
 about_bullets_invoices=[
    "Выставление счетов/чеков физлицам с созданием PDF",
    "Сохранённые контрагенты — выбор покупателя из списка в одно касание",
    "Статусы: Оплачен / Ожидает оплаты / Просрочен, плюс напоминания о сроке оплаты",
    "Контроль годового лимита наличных (20 000 zł) для продаж физлицам",
    "История счетов с поиском и фильтрами"],
 about_bullets_reports=[
    "Сводка доходов/расходов и график тренда за 6 месяцев",
    "Экспорт месячного отчёта (бесплатно), годового и за произвольный период (Pro) в Excel с чеками",
    "Ewidencja sprzedaży в PDF за месяц, квартал, год или произвольный период (Pro)",
    "Формирование декларации PIT-36 — вспомогательный PDF и заполнение официальной формы (Pro)"],
)

L["values-uk"] = dict(
 paywall_feature_1="Без ліміту на доходи й витрати",
 paywall_feature_2="Склад: сканер штрих-кодів, залишки та інвентаризація",
 paywall_feature_3="Рахунки та чеки (PDF), збережені контрагенти",
 paywall_feature_4="Декларація PIT-36 і Ewidencja sprzedaży (PDF)",
 paywall_feature_5="Річні та довільні звіти Excel",
 paywall_feature_6="Регулярні записи та нагадування про PIT і аванси",
 paywall_feature_7="Резервне копіювання й відновлення даних",
 paywall_feature_8="Без реклами",
 pro_status_locked="Pro заблоковано. Розблокуйте, щоб зняти місячний ліміт записів і отримати склад, рахунки, звіти, резервне копіювання та інше.",
 pro_info_message=info("Pro відкриває:", [
    "Без ліміту на доходи й витрати (безкоштовний план: 30 + 30 на місяць)",
    "Склад: сканування штрих-кодів, залишки, інвентаризація, сповіщення про низький залишок",
    "Рахунки та чеки (PDF), збережені контрагенти",
    "Декларація PIT-36 і Ewidencja sprzedaży (PDF)",
    "Річні та довільні звіти Excel",
    "Регулярні записи, нагадування про строк PIT і аванси",
    "Резервне копіювання й відновлення",
    "Без реклами"]),
 tour_pro_text="Pro знімає місячний ліміт записів і відкриває склад, рахунки та фактури (PDF), збережених контрагентів, PIT-36 та Ewidencja sprzedaży у PDF, річний і довільний звіти в Excel, регулярні записи, нагадування про строк PIT і аванси, резервне копіювання й відновлення та прибирає рекламу. Починається з 7 днів безкоштовно.",
 tour_bell_text="Тут з’являються нагадування про ліміти, низький залишок, терміни рахунків і річний строк PIT. Попередження про ліміти безкоштовні; сповіщення про залишки та нагадування про PIT — у Pro.",
 tour_add_text="Натисніть +, щоб додати дохід або витрату: сума, дата, категорія, коментар і вкладення, наприклад фото чека. Запис можна зробити регулярним (Pro). Безкоштовний план: до 30 доходів і 30 витрат на місяць.",
 tour_magazin_text="Керуйте товарами та залишками: додавайте позиції вручну або сканером штрих-кодів, проводьте інвентаризацію й отримуйте сповіщення про низький залишок. Склад — це функція Pro.",
 tour_reports_text="Оберіть період, щоб побачити структуру доходів, витрат і податку. Місячний звіт експортується в Excel безкоштовно; річний і довільний звіти та Ewidencja sprzedaży у PDF — Pro.",
 about_subscription_note="⭐ Безкоштовний план: до 30 доходів і 30 витрат на місяць, місячний звіт, контроль ліміту та попередження, PIN-блокування. Підписка Pro: місячний або річний план, 7 днів безкоштовно, скасування в будь-який час.",
 about_section_warehouse_title="📦 Склад (Pro)",
)
L["values-uk"]["_arrays"] = dict(
 about_bullets_finance=[
    "Облік доходів і витрат із прикріпленими чеками та кольоровими категоріями",
    "Безкоштовний план: до 30 доходів і 30 витрат на місяць — Pro знімає обмеження",
    "Автоматичний розрахунок прибутку та податку (шкала 12%/32%)",
    "Регулярні операції (оренда, підписки), що створюються автоматично щомісяця (Pro)",
    "Контроль ліміту незареєстрованої діяльності (поріг 120 000 zł)",
    "Попередження про наближення та перевищення лімітів (безкоштовно); нагадування про строк PIT і аванси (Pro)"],
 about_bullets_invoices=[
    "Виставлення рахунків/чеків фізичним особам із генерацією PDF",
    "Збережені контрагенти — вибір покупця зі списку одним дотиком",
    "Статуси: Оплачено / Очікує / Прострочено, плюс нагадування про терміни оплати",
    "Контроль річного ліміту готівкових продажів фізособам у 20 000 zł",
    "Історія рахунків із пошуком і фільтрами"],
 about_bullets_reports=[
    "Зведення доходів/витрат і графік тренду за 6 місяців",
    "Експорт місячного звіту (безкоштовно), річного та за довільний період (Pro) в Excel із чеками",
    "Ewidencja sprzedaży у PDF за місяць, квартал, рік або довільний період (Pro)",
    "Формування декларацій PIT-36 — допоміжний PDF і заповнення офіційної форми (Pro)"],
)

# ------------------------------------------------------------------ строки
for folder, data in L.items():
    p = R + "/" + folder + "/strings.xml"
    s = read(p)
    if 'name="paywall_feature_8"' in s:
        print(folder + "/strings.xml: уже применено")
        continue
    arrays = data["_arrays"]
    for name, value in data.items():
        if name == "_arrays":
            continue
        if name == "paywall_feature_6":
            pass
        if name in ("paywall_feature_6", "paywall_feature_7", "paywall_feature_8"):
            # новые строки — добавляем после paywall_feature_5
            m = re.search(r'<string name="paywall_feature_5">.*?</string>\n', s, re.S)
            assert m, "paywall_feature_5 не найден"
            continue
        s = set_string(s, name, value)
    # новые строки paywall_feature_6..8 одним блоком после paywall_feature_5
    m = re.search(r'(<string name="paywall_feature_5">.*?</string>\n)', s, re.S)
    add = "".join('    <string name="paywall_feature_%d">%s</string>\n' % (i, data["paywall_feature_%d" % i]) for i in (6, 7, 8))
    s = s[:m.end()] + add + s[m.end():]
    for name, items in arrays.items():
        s = set_array(s, name, items)
    write(p, s)

# ------------------------------------------------------------------ экран подписки: 8 пунктов
p = R + "/layout/activity_settings_pro.xml"
s = read(p)
if "paywall_feature_8" in s:
    print("activity_settings_pro.xml: уже применено")
else:
    start = s.index("        <!-- Feature list -->")
    end = s.index("        <!-- Yearly plan card")
    rows = ""
    for i in range(1, 9):
        mb = ' android:layout_marginBottom="14dp"' if i < 8 else ""
        rows += (
            '            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"\n'
            '                android:orientation="horizontal" android:gravity="center_vertical"%s>\n'
            '                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>\n'
            '                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"\n'
            '                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_%d"\n'
            '                    android:textColor="@color/text_primary" android:textSize="15sp"/>\n'
            '            </LinearLayout>\n\n' % (mb, i)
        )
    block = (
        "        <!-- Feature list (Update 81: 8 пунктов) -->\n"
        "        <LinearLayout\n"
        '            android:layout_width="match_parent" android:layout_height="wrap_content"\n'
        '            android:orientation="vertical" android:layout_marginTop="26dp">\n\n'
        + rows.rstrip("\n") + "\n"
        "        </LinearLayout>\n\n"
    )
    s = s[:start] + block + s[end:]
    write(p, s)


# ====================================================================
# Единый диалог "функция Pro" (замок + кнопка перехода к подписке) для УЖЕ существующих
# Pro-кнопок: фактуры, PIT-36, резервная копия, годовой/произвольный отчёты.
# ====================================================================
def rep_re(s, pattern, new, what):
    assert len(re.findall(pattern, s, re.S)) == 1, "не найден (или не уникален) блок: " + what
    return re.sub(pattern, lambda _m: new, s, flags=re.S)

def refactor(path, pattern, new, done_marker, what):
    s = read(path)
    if done_marker in s:
        print(what + ": уже применено")
        return
    write(path, rep_re(s, pattern, new, what))

JJ = "app/src/main/java/com/example/fa_ksiegowy"
refactor(JJ + "/AddEntryActivity.kt",
    r"            if \(BillingManager\.isPro\(this\)\) \{\n\s+startActivity\(Intent\(this, AddInvoiceActivity::class\.java\)\)\n\s+finish\(\)\n\s+\} else \{.*?\.show\(\)\n            \}\n",
    "            // Update 80: единый диалог Pro (замок + переход к подписке).\n"
    "            ProGate.require(this, R.string.invoice_pro_locked_message) {\n"
    "                startActivity(Intent(this, AddInvoiceActivity::class.java))\n"
    "                finish()\n"
    "            }\n",
    "ProGate.require(this, R.string.invoice_pro_locked_message) {\n                startActivity(Intent(this, AddInvoiceActivity", "AddEntryActivity (фактура)")

refactor(JJ + "/MineFragment.kt",
    r"            if \(BillingManager\.isPro\(requireContext\(\)\)\) \{\n\s+startActivity\(Intent\(requireContext\(\), AddInvoiceActivity::class\.java\)\)\n\s+\} else \{.*?\.show\(\)\n            \}\n",
    "            // Update 80: единый диалог Pro (замок + переход к подписке).\n"
    "            ProGate.require(requireContext(), R.string.invoice_pro_locked_message) {\n"
    "                startActivity(Intent(requireContext(), AddInvoiceActivity::class.java))\n"
    "            }\n",
    "ProGate.require(requireContext(), R.string.invoice_pro_locked_message)", "MineFragment (фактуры)")

refactor(JJ + "/SettingsFragment.kt",
    r"            if \(BillingManager\.isPro\(requireContext\(\)\)\) \{\n\s+startActivity\(Intent\(requireContext\(\), Pit36Activity::class\.java\)\)\n\s+\} else \{.*?\.show\(\)\n            \}\n",
    "            // Update 80: единый диалог Pro (замок + переход к подписке).\n"
    "            ProGate.require(requireContext(), R.string.pit36_pro_locked_message) {\n"
    "                startActivity(Intent(requireContext(), Pit36Activity::class.java))\n"
    "            }\n",
    "ProGate.require(requireContext(), R.string.pit36_pro_locked_message)", "SettingsFragment (PIT-36)")

refactor(JJ + "/SettingsFragment.kt",
    r"            if \(BillingManager\.isPro\(requireContext\(\)\)\) \{\n\s+startActivity\(Intent\(requireContext\(\), SettingsBackupActivity::class\.java\)\)\n\s+\} else \{.*?\.show\(\)\n            \}\n",
    "            // Update 80: единый диалог Pro (замок + переход к подписке).\n"
    "            ProGate.require(requireContext(), R.string.backup_pro_locked_message) {\n"
    "                startActivity(Intent(requireContext(), SettingsBackupActivity::class.java))\n"
    "            }\n",
    "ProGate.require(requireContext(), R.string.backup_pro_locked_message)", "SettingsFragment (бэкап)")

refactor(JJ + "/ReportFragment.kt",
    r"    private fun runIfPro\(action: \(\) -> Unit\) \{.*?\n    \}\n",
    "    private fun runIfPro(action: () -> Unit) {\n"
    "        // Update 80: единый диалог Pro (замок + переход к подписке).\n"
    "        ProGate.require(requireContext(), R.string.pro_feature_locked_message, action)\n"
    "    }\n",
    "ProGate.require(requireContext(), R.string.pro_feature_locked_message, action)", "ReportFragment (runIfPro)")

print("\nГотово. Update 80 применён.")
PY

echo "Update 80 OK. Теперь: git add -A && git commit -m 'Update 80: Pro gating' && git push"
