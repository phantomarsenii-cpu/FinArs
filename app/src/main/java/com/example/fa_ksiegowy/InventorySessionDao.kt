package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InventorySessionDao {
    @Insert
    suspend fun insert(session: InventorySession): Long

    @Query("SELECT * FROM inventory_sessions ORDER BY dateMillis DESC")
    suspend fun getAll(): List<InventorySession>

    @Query("SELECT COUNT(*) FROM inventory_sessions")
    suspend fun count(): Int

    @Delete
    suspend fun delete(session: InventorySession)
}
