package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface RecurringEntryDao {
    @Insert
    suspend fun insert(entry: RecurringEntry): Long

    @Update
    suspend fun update(entry: RecurringEntry)

    @Delete
    suspend fun delete(entry: RecurringEntry)

    @Query("SELECT * FROM recurring_entries WHERE active = 1 ORDER BY dayOfMonth ASC")
    suspend fun getAllActive(): List<RecurringEntry>

    /** Wszystkie aktywne szablony, których termin (nextRunMillis) już nadszedł — używane przez worker. */
    @Query("SELECT * FROM recurring_entries WHERE active = 1 AND nextRunMillis <= :now")
    suspend fun getDue(now: Long): List<RecurringEntry>
}
