package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface InvoiceDao {
    @Insert
    suspend fun insert(invoice: Invoice): Long

    @Update
    suspend fun update(invoice: Invoice)

    @Delete
    suspend fun delete(invoice: Invoice)

    @Query("SELECT * FROM invoices WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Invoice?

    @Query("SELECT * FROM invoices ORDER BY issueDateMillis DESC")
    suspend fun getAll(): List<Invoice>

    @Query("SELECT MAX(invoiceNumber) FROM invoices")
    suspend fun getMaxInvoiceNumber(): Int?

    /**
     * Suma sprzedaży gotówkowej (paymentMethod = CASH) dla osób fizycznych
     * w danym roku — podstawa kontrolki limitu 20 000 PLN (kasa fiskalna).
     * Filtrowanie po isPhysicalPerson i paymentMethod robimy w Kotlinie
     * (patrz CashLimitHelper), tu pobieramy tylko zakres dat, by uniknąć
     * przechowywania enuma jako String w zapytaniu SQL.
     */
    @Query("SELECT * FROM invoices WHERE issueDateMillis BETWEEN :from AND :to ORDER BY issueDateMillis ASC")
    suspend fun getBetween(from: Long, to: Long): List<Invoice>

    /** Неоплаченные фактуры, отсортированные по ближайшему сроку — для напоминаний и фильтра статуса. */
    @Query("SELECT * FROM invoices WHERE status = 'PENDING' ORDER BY dueDateMillis ASC")
    suspend fun getPending(): List<Invoice>
}
