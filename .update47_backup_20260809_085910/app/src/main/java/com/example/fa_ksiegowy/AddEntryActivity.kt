package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Экран добавления ИЛИ редактирования операции.
 * Если в intent передан "entryId" (id существующей записи) — режим редактирования:
 * поля предзаполняются, появляется кнопка удаления, а сохранение обновляет запись
 * вместо создания новой. Без "entryId" работает как раньше — создание новой записи.
 *
 * Сканирование чека (распознавание суммы/даты по фото, ML Kit OCR — "Skanuj paragon"
 * и "Skanuj paragon z galerii") убрано полностью — осталось только обычное
 * прикрепление фото чека без автозаполнения (btn_attach).
 *
 * Для приходов, когда в настройках выбрана форма ActivityType.JDG_RYCZALT,
 * появляется обязательный выбор категории ryczałtu (см. RyczaltCategory) — ставка
 * (3%/5,5%/8,5%/12%/14%/17%) теперь привязана к конкретной операции, а не к одной
 * общей настройке, так как один человек может одновременно продавать товары и
 * оказывать разные услуги.
 */
class AddEntryActivity : BaseActivity() {
    private var selectedImagePath: String? = null
    private var editingEntry: Entry? = null
    private var currentIsIncome: Boolean = true
    // Дата транзакции (Data sprzedaży / Data transakcji) — по умолчанию сегодня,
    // но пользователь может выбрать любую дату через DatePickerDialog. Это важно,
    // так как лимиты działalność nierejestrowana считаются строго по месяцам/кварталам,
    // и запись должна попадать в правильный период, а не всегда в "сейчас".
    private var selectedDateMillis: Long = System.currentTimeMillis()
    // Повтор доступен только при создании новой записи (не при редактировании
    // существующей) — иначе неясно, что должно произойти с уже созданными
    // на основе шаблона транзакциями.
    private var wantsRecurring: Boolean = false

    // Категория ryczałtu для этого дохода — актуальна только когда currentIsIncome==true
    // и в настройках выбран ActivityType.JDG_RYCZALT (см. updateTypeToggleUi/RyczaltCategory).
    private var selectedRyczaltCategory: String? = null
    private val activityType: ActivityType by lazy {
        ActivityTypeHelper.get(getSharedPreferences("settings", MODE_PRIVATE))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_entry)

        val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            if (uri == null) return@registerForActivityResult
            try {
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    Toast.makeText(this, "Не удалось открыть файл", Toast.LENGTH_SHORT).show()
                    return@registerForActivityResult
                }
                // Временное имя: окончательное стандартизированное имя
                // (YYYY-MM-DD_TYPE_AMOUNT_ID.jpg) присваивается при сохранении записи,
                // когда известны дата операции, сумма, тип и id (см. renameReceiptToStandardName).
                val out = File(getExternalFilesDir(null), "receipt_tmp_${System.currentTimeMillis()}.jpg")
                FileOutputStream(out).use { fos -> input.copyTo(fos) }
                input.close()
                selectedImagePath = out.absolutePath
                findViewById<Button>(R.id.btn_attach).text = getString(R.string.attach_receipt) + " ✓"
                Toast.makeText(this, "Чек добавлен", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Ошибка при добавлении чека: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }

        val entryId = intent.getLongExtra("entryId", -1L)
        currentIsIncome = intent.getBooleanExtra("isIncome", true)

        setupTypeToggle()
        findViewById<Button>(R.id.btn_attach).setOnClickListener { pickImage.launch("image/*") }
        findViewById<Button>(R.id.btn_delete).setOnClickListener { confirmDelete() }
        findViewById<Button>(R.id.btn_date).setOnClickListener { showDatePicker() }
        findViewById<Button>(R.id.btn_ryczalt_category).setOnClickListener { showRyczaltCategoryPicker() }
        findViewById<android.widget.Switch>(R.id.sw_recurring).setOnCheckedChangeListener { _, checked ->
            wantsRecurring = checked
        }

        updateTypeToggleUi()
        updateTitle()
        updateDateButtonText()
        updateRyczaltCategoryButtonText()

        if (entryId != -1L) {
            findViewById<Button>(R.id.btn_delete).visibility = View.VISIBLE
            findViewById<View>(R.id.row_recurring).visibility = View.GONE
            CoroutineScope(Dispatchers.IO).launch {
                val entry = AppDatabase.getInstance(applicationContext).entryDao().getById(entryId)
                withContext(Dispatchers.Main) {
                    if (entry == null) {
                        Toast.makeText(this@AddEntryActivity, "Запись не найдена", Toast.LENGTH_SHORT).show()
                        finish()
                        return@withContext
                    }
                    editingEntry = entry
                    currentIsIncome = entry.isIncome
                    findViewById<EditText>(R.id.et_amount).setText(formatAmount(entry.amount))
                    findViewById<EditText>(R.id.et_comment).setText(entry.comment ?: "")
                    selectedImagePath = entry.receiptPath
                    selectedDateMillis = entry.dateMillis
                    selectedRyczaltCategory = entry.ryczaltCategory
                    if (entry.receiptPath != null) {
                        findViewById<Button>(R.id.btn_attach).text = getString(R.string.attach_receipt) + " ✓"
                    }
                    updateTypeToggleUi()
                    updateTitle()
                    updateDateButtonText()
                    updateRyczaltCategoryButtonText()
                }
            }
        }

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            val amt = findViewById<EditText>(R.id.et_amount).text.toString().toDoubleOrNull()
            if (amt == null || amt <= 0.0) {
                Toast.makeText(this, "Введите корректную сумму", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT && selectedRyczaltCategory == null) {
                Toast.makeText(this, getString(R.string.income_ryczalt_category_required_error), Toast.LENGTH_LONG).show()
                return@setOnClickListener
            }
            val comment = findViewById<EditText>(R.id.et_comment).text.toString()
            findViewById<Button>(R.id.btn_save).isEnabled = false

            // Категория ryczałtu имеет смысл только для приходов при форме ryczałt —
            // для расходов и других форм налогообложения запись сохраняем с null.
            val categoryToSave = if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT) selectedRyczaltCategory else null

            val existing = editingEntry
            CoroutineScope(Dispatchers.IO).launch {
                val dao = AppDatabase.getInstance(applicationContext).entryDao()
                val finalReceiptPath = renameReceiptToStandardName(
                    selectedImagePath, selectedDateMillis, currentIsIncome, amt, existing?.id
                )
                if (existing != null) {
                    dao.update(
                        existing.copy(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath,
                            ryczaltCategory = categoryToSave
                        )
                    )
                } else {
                    val newId = dao.insert(
                        Entry(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath,
                            ryczaltCategory = categoryToSave
                        )
                    )
                    // Имя файла чека включает id записи — при создании id известен только
                    // после insert, поэтому для новых записей переименовываем повторно.
                    val renamedAgain = renameReceiptToStandardName(
                        finalReceiptPath, selectedDateMillis, currentIsIncome, amt, newId
                    )
                    if (renamedAgain != finalReceiptPath) {
                        dao.update(
                            Entry(
                                id = newId, amount = amt, isIncome = currentIsIncome,
                                comment = comment, dateMillis = selectedDateMillis, receiptPath = renamedAgain,
                                ryczaltCategory = categoryToSave
                            )
                        )
                    }
                    if (wantsRecurring) {
                        val cal = java.util.Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
                        val dayOfMonth = cal.get(java.util.Calendar.DAY_OF_MONTH).coerceIn(1, 28)
                        cal.add(java.util.Calendar.MONTH, 1)
                        cal.set(java.util.Calendar.DAY_OF_MONTH, dayOfMonth)
                        AppDatabase.getInstance(applicationContext).recurringEntryDao().insert(
                            RecurringEntry(
                                amount = amt,
                                isIncome = currentIsIncome,
                                comment = comment,
                                dayOfMonth = dayOfMonth,
                                nextRunMillis = cal.timeInMillis
                            )
                        )
                    }
                }
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@AddEntryActivity,
                        getString(if (existing != null) R.string.entry_updated else R.string.saved),
                        Toast.LENGTH_SHORT
                    ).show()
                    finish()
                }
            }
        }
    }

    private fun setupTypeToggle() {
        findViewById<Button>(R.id.btn_type_income).setOnClickListener {
            currentIsIncome = true
            updateTypeToggleUi()
            updateTitle()
        }
        findViewById<Button>(R.id.btn_type_expense).setOnClickListener {
            currentIsIncome = false
            updateTypeToggleUi()
            updateTitle()
        }
    }

    private fun updateTypeToggleUi() {
        val income = findViewById<Button>(R.id.btn_type_income)
        val expense = findViewById<Button>(R.id.btn_type_expense)
        // Явное выделение выбранного варианта — тот же приём, что и для способа оплаты
        // на экране фактуры: яркий фон + белый текст против приглушённого фона и
        // серого текста у невыбранного варианта.
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        income.setTextColor(resources.getColor(if (currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        expense.setTextColor(resources.getColor(if (!currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        income.alpha = if (currentIsIncome) 1.0f else 0.75f
        expense.alpha = if (!currentIsIncome) 1.0f else 0.75f
        // Прикладывать чек имеет смысл только для расходов (чек подтверждает трату) —
        // для приходов эта кнопка только путает.
        findViewById<Button>(R.id.btn_attach).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
        // Категория ryczałtu, наоборот, актуальна только для ПРИХОДОВ и только при
        // форме налогообложения ryczałt — во всех остальных случаях скрыта.
        findViewById<Button>(R.id.btn_ryczalt_category).visibility =
            if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT) View.VISIBLE else View.GONE
    }

    private fun updateTitle() {
        val isEditing = editingEntry != null
        val titleRes = when {
            isEditing && currentIsIncome -> R.string.edit_income_title
            isEditing && !currentIsIncome -> R.string.edit_expense_title
            currentIsIncome -> R.string.add_income
            else -> R.string.add_expense
        }
        findViewById<TextView>(R.id.tv_add_title).text = getString(titleRes)
    }

    /** Небольшое стилизованное вертикальное меню (см. AppDialog) для выбора категории
     *  ryczałtu этого прихода — от неё зависит применяемая ставка налога. */
    private fun showRyczaltCategoryPicker() {
        AppDialog.showOptionPicker(
            context = this,
            title = getString(R.string.ryczalt_category_picker_title),
            options = RyczaltCategory.entries.map { it.name to getString(it.labelRes) }
        ) { selected ->
            selectedRyczaltCategory = selected
            updateRyczaltCategoryButtonText()
        }
    }

    private fun updateRyczaltCategoryButtonText() {
        val btn = findViewById<Button>(R.id.btn_ryczalt_category)
        val cat = RyczaltCategory.fromStorageKeyOrNull(selectedRyczaltCategory)
        btn.text = if (cat != null) getString(R.string.ryczalt_category_selected, getString(cat.labelRes))
        else getString(R.string.ryczalt_category_choose)
    }

    private fun confirmDelete() {
        val entry = editingEntry ?: return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).entryDao().delete(entry)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@AddEntryActivity, getString(R.string.entry_deleted), Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    /** Без лишних нулей для целых сумм (100, а не 100.0), но с сохранением копеек, если они есть. */
    private fun formatAmount(v: Double): String =
        if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

    /** Открывает системный DatePickerDialog, предзаполненный текущей выбранной датой. */
    private fun showDatePicker() {
        val cal = Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply {
                    set(year, month, dayOfMonth, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                selectedDateMillis = picked.timeInMillis
                updateDateButtonText()
            },
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH),
            cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    /**
     * Переименовывает файл чека (если он есть) в стандартизированный формат
     * `YYYY-MM-DD_TYPE_AMOUNT_ID.jpg` (см. FileNaming) для удобной сортировки
     * и архивации перед подачей в налоговую. Если id ещё не известен
     * (новая запись до insert), используется 0 — сразу после insert
     * файл переименовывается ещё раз с настоящим id.
     */
    private fun renameReceiptToStandardName(
        path: String?, dateMillis: Long, isIncome: Boolean, amount: Double, entryId: Long?
    ): String? {
        if (path == null) return null
        val current = File(path)
        if (!current.exists()) return path
        val ext = current.extension.ifBlank { "jpg" }
        val newName = FileNaming.receiptFileName(dateMillis, isIncome, amount, entryId ?: 0L, ext)
        val newFile = File(current.parentFile, newName)
        if (newFile.absolutePath == current.absolutePath) return path
        return try {
            if (current.renameTo(newFile)) newFile.absolutePath else path
        } catch (e: Exception) {
            path
        }
    }

    /** Обновляет текст кнопки даты в формате dd.MM.yyyy (польский/общеевропейский формат). */
    private fun updateDateButtonText() {
        val sdf = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val formatted = sdf.format(selectedDateMillis)
        findViewById<Button>(R.id.btn_date).text =
            getString(R.string.entry_date_label) + ": " + formatted
    }
}
