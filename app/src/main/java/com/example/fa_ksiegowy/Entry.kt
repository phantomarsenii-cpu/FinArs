package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "entries")
data class Entry(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val amount: Double,
    val isIncome: Boolean,
    val comment: String?,
    val dateMillis: Long,
    val receiptPath: String?,
    // Категория ryczałtu (см. RyczaltCategory), к которой относится этот доход —
    // заполняется только для приходов, когда в настройках выбран
    // ActivityType.JDG_RYCZALT (см. AddEntryActivity). Разные категории облагаются
    // разными ставками (3%/5,5%/8,5%/12%/14%/17%), поэтому это не глобальная
    // настройка, а свойство конкретной операции — один и тот же человек может
    // одновременно продавать товары и оказывать услуги. Null для расходов и для
    // записей, созданных при других формах налогообложения.
    val ryczaltCategory: String? = null,
    // Если этот приход был создан АВТОМАТИЧЕСКИ при выставлении фактуры/корректы —
    // здесь хранится id соответствующей Invoice/InvoiceCorrection. Используется,
    // чтобы при удалении фактуры/корректы из истории (см. InvoiceHistoryActivity)
    // автоматически удалить и этот приход — иначе он оставался бы в Historii и
    // продолжал бы учитываться в балансе/лимите/налоге, хотя самой фактуры
    // (и, соответственно, дохода, который она подтверждала) уже нет. Null для
    // всех обычных, вручную добавленных операций.
    val invoiceId: Long? = null,
    val invoiceCorrectionId: Long? = null
)
