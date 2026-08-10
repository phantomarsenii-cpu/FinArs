package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одна позиция многопозиционной фактуры. productId == null означает, что
 * позиция была добавлена вручную, а не выбрана со склада (склад не затрагивается).
 */
@Entity(tableName = "invoice_items")
data class InvoiceItem(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val invoiceId: Long,
    val productId: Long?,
    val name: String,
    val quantity: Double,
    val unitPrice: Double
)
