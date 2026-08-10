package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InventoryRecordDao {
    @Insert
    suspend fun insert(record: InventoryRecord): Long

    @Query("SELECT * FROM inventory_records ORDER BY dateMillis DESC")
    suspend fun getAll(): List<InventoryRecord>

    @Query("SELECT * FROM inventory_records WHERE productId = :productId ORDER BY dateMillis DESC")
    suspend fun getForProduct(productId: Long): List<InventoryRecord>
}
