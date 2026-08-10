package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Запись о результате инвентаризации одного товара: сколько было по учёту и
 * сколько насчитал пользователь при физической проверке склада. Хранится даже
 * если разница равна нулю (подтверждение, что товар проверялся) — так по
 * dateMillis можно увидеть, когда в последний раз делалась инвентаризация.
 */
@Entity(tableName = "inventory_records")
data class InventoryRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val productId: Long,
    val productName: String,
    val unit: String,
    val quantityBefore: Double,
    val quantityCounted: Double,
    val dateMillis: Long = System.currentTimeMillis()
) {
    val diff: Double get() = quantityCounted - quantityBefore
}
