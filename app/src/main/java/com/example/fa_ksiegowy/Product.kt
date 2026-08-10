package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Товар на складе. barcode может быть null для товаров, добавленных вручную без сканирования.
 * priceNet — цена ЗАКУПКИ (себестоимость), priceSell — цена ПРОДАЖИ (используется при
 * добавлении товара в фактуру). priceSell можно ввести вручную конкретной суммой ИЛИ
 * через marginPercent (наценка в % от цены закупки) — оба поля всегда синхронизированы
 * между собой на экране редактирования товара, marginPercent хранится только как снимок
 * эффективной наценки на момент последнего сохранения (для удобства повторного редактирования).
 */
@Entity(tableName = "products")
data class Product(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val barcode: String?,
    val name: String,
    val quantity: Double,
    val unit: String = "szt.",
    val lowStockThreshold: Double = 5.0,
    val priceNet: Double = 0.0,
    val priceSell: Double = 0.0,
    val marginPercent: Double = 0.0,
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val isLowStock: Boolean get() = quantity <= lowStockThreshold
}
