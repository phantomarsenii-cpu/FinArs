package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InvoiceCorrectionDao {
    @Insert
    suspend fun insert(correction: InvoiceCorrection): Long

    @Delete
    suspend fun delete(correction: InvoiceCorrection)

    @Query("SELECT * FROM invoice_corrections WHERE originalInvoiceId = :invoiceId ORDER BY issueDateMillis ASC")
    suspend fun getForInvoice(invoiceId: Long): List<InvoiceCorrection>

    @Query("SELECT * FROM invoice_corrections ORDER BY issueDateMillis DESC")
    suspend fun getAll(): List<InvoiceCorrection>

    @Query("SELECT MAX(correctionNumber) FROM invoice_corrections")
    suspend fun getMaxCorrectionNumber(): Int?
}

