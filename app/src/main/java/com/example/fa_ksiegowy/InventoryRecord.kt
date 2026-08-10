package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Запись о результате инвентаризации одного товара внутри конкретной сессии
 * инвентаризации ([InventorySession], sessionId) — сколько было по учёту и
 * сколько насчитал пользователь при физической проверке склада. Хранится
 * только для товаров с расхождением (см. InventoryActivity.saveInventory).
 * priceNetAtInventory — себестоимость товара (цена закупки) НА МОМЕНТ инвентаризации
 * (снимок Product.priceNet), priceSellAtInventory — цена продажи товара на тот же момент
 * (снимок Product.priceSell), чтобы денежная разница (и по себестоимости, и упущенная/лишняя
 * выручка по цене продажи) в истории и PDF не "плыла" задним числом при последующем изменении
 * цены товара.
 */
@Entity(tableName = "inventory_records")
data class InventoryRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionId: Long = 0,
    val productId: Long,
    val productName: String,
    val unit: String,
    val quantityBefore: Double,
    val quantityCounted: Double,
    val priceNetAtInventory: Double = 0.0,
    val priceSellAtInventory: Double = 0.0,
    val dateMillis: Long = System.currentTimeMillis()
) {
    val diff: Double get() = quantityCounted - quantityBefore
    val diffValue: Double get() = diff * priceNetAtInventory
    val diffValueSell: Double get() = diff * priceSellAtInventory
}
