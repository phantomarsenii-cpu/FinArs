package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface EntryDao {
    @Insert
    suspend fun insert(entry: Entry): Long

    @Update
    suspend fun update(entry: Entry)

    @Delete
    suspend fun delete(entry: Entry)

    @Query("SELECT * FROM entries WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Entry?

    @Query("SELECT * FROM entries ORDER BY dateMillis DESC")
    suspend fun getAll(): List<Entry>

    @Query("SELECT * FROM entries WHERE dateMillis BETWEEN :from AND :to ORDER BY dateMillis ASC")
    suspend fun getBetween(from: Long, to: Long): List<Entry>

    /** Полная очистка истории — используется кнопкой "Очистить все данные" в настройках. */
    @Query("DELETE FROM entries")
    suspend fun deleteAll()
}
