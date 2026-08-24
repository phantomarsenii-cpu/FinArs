package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface ContractorDao {
    @Insert
    suspend fun insert(contractor: Contractor): Long

    @Update
    suspend fun update(contractor: Contractor)

    @Delete
    suspend fun delete(contractor: Contractor)

    @Query("SELECT * FROM contractors WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Contractor?

    /** Używane przy "Zapisz nabywcę" — jeśli kontrahent o tej samej nazwie już
     *  istnieje, aktualizujemy jego dane zamiast tworzyć duplikat. */
    @Query("SELECT * FROM contractors WHERE name = :name LIMIT 1")
    suspend fun getByName(name: String): Contractor?

    @Query("SELECT * FROM contractors ORDER BY name ASC")
    suspend fun getAll(): List<Contractor>
}
