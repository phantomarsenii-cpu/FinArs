package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Товар на складе. barcode может быть null для товаров, добавленных вручную без сканирования. */
@Entity(tableName = "products")
data class Product(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val barcode: String?,
    val name: String,
    val quantity: Double,
    val unit: String = "szt.",
    val lowStockThreshold: Double = 5.0,
    val priceNet: Double = 0.0,
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val isLowStock: Boolean get() = quantity <= lowStockThreshold
}
