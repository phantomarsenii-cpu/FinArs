package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * История всех проведённых инвентаризаций склада. Тап по строке открывает
 * сохранённый PDF-отчёт этой инвентаризации в системном просмотрщике; кнопка
 * "✕" удаляет ошибочную инвентаризацию (запись из БД, связанные записи
 * расхождений и сам PDF-файл) после подтверждения.
 */
class InventoryHistoryActivity : BaseActivity() {
    private lateinit var adapter: InventorySessionAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_inventory_history)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        adapter = InventorySessionAdapter(
            onItemClick = { session -> openSessionPdf(session) },
            onDeleteClick = { session -> confirmDelete(session) }
        )
        findViewById<RecyclerView>(R.id.rv_inventory_sessions).apply {
            layoutManager = LinearLayoutManager(this@InventoryHistoryActivity)
            adapter = this@InventoryHistoryActivity.adapter
        }

        loadData()
    }

    override fun onResume() {
        super.onResume()
        loadData()
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            val sessions = AppDatabase.getInstance(applicationContext).inventorySessionDao().getAll()
            withContext(Dispatchers.Main) {
                adapter.submitList(sessions)
                findViewById<TextView>(R.id.tv_inventory_history_empty).visibility =
                    if (sessions.isEmpty()) View.VISIBLE else View.GONE
            }
        }
    }

    private fun openSessionPdf(session: InventorySession) {
        val opened = InventoryFileStorage.openPdfSafely(this, session.pdfFilePath)
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InventoryFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    private fun confirmDelete(session: InventorySession) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    val db = AppDatabase.getInstance(applicationContext)
                    InventoryFileStorage.deleteFile(applicationContext, session.pdfFilePath)
                    db.inventoryRecordDao().deleteForSession(session.id)
                    db.inventorySessionDao().delete(session)
                    withContext(Dispatchers.Main) { loadData() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
