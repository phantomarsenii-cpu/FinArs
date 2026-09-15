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

    /** Удаляет приход(ы), автоматически созданные при выставлении конкретной фактуры —
     *  вызывается при удалении самой фактуры из истории (InvoiceHistoryActivity),
     *  чтобы доход не "завис" в Historii и не продолжал учитываться в балансе/налоге.
     *  Обычно одна фактура = один приход, но для JDG_RYCZALT со смешанными категориями
     *  на одну фактуру может приходиться несколько приходов (по одному на категорию) —
     *  поэтому удаление по invoiceId, а не по одиночному id. */
    @Query("DELETE FROM entries WHERE invoiceId = :invoiceId")
    suspend fun deleteByInvoiceId(invoiceId: Long)

    /** То же самое, но для прихода, созданного корректой (см. AddInvoiceCorrectionActivity,
     *  appliedToIncome) — вызывается при удалении korekty из истории. */
    @Query("DELETE FROM entries WHERE invoiceCorrectionId = :invoiceCorrectionId")
    suspend fun deleteByInvoiceCorrectionId(invoiceCorrectionId: Long)
}
