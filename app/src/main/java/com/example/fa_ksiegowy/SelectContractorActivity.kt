package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Lista zapisanych kontrahentów (nabywców) — wybór jednego z nich zwraca jego
 * id do AddInvoiceActivity (extra "picked_contractor_id"), gdzie dane są
 * wczytywane i wypełniają sekcję "Nabywca". Kontrahentów można też stąd
 * usuwać (przycisk ✕ z potwierdzeniem, tak jak w innych listach aplikacji).
 */
class SelectContractorActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_select_contractor)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        loadContractors()
    }

    private fun loadContractors() {
        CoroutineScope(Dispatchers.IO).launch {
            val all = AppDatabase.getInstance(applicationContext).contractorDao().getAll()
            withContext(Dispatchers.Main) { renderList(all) }
        }
    }

    private fun renderList(contractors: List<Contractor>) {
        val container = findViewById<LinearLayout>(R.id.ll_contractors_container)
        val empty = findViewById<TextView>(R.id.tv_contractors_empty)
        container.removeAllViews()

        if (contractors.isEmpty()) {
            empty.visibility = android.view.View.VISIBLE
            return
        }
        empty.visibility = android.view.View.GONE

        val inflater = LayoutInflater.from(this)
        for (c in contractors) {
            val row = inflater.inflate(R.layout.item_contractor_select, container, false)
            row.findViewById<TextView>(R.id.tv_contractor_name).text = c.name

            val metaParts = mutableListOf<String>()
            if (!c.nip.isNullOrBlank()) metaParts.add("NIP: ${c.nip}")
            if (c.city.isNotBlank()) metaParts.add(c.city)
            row.findViewById<TextView>(R.id.tv_contractor_meta).text = metaParts.joinToString(" • ")

            row.setOnClickListener { pickContractor(c) }
            row.findViewById<TextView>(R.id.btn_delete_contractor).setOnClickListener { confirmDelete(c) }

            container.addView(row)
        }
    }

    private fun pickContractor(contractor: Contractor) {
        val i = Intent()
        i.putExtra("picked_contractor_id", contractor.id)
        setResult(RESULT_OK, i)
        finish()
    }

    private fun confirmDelete(contractor: Contractor) {
        AppDialog.show(
            context = this,
            title = getString(R.string.delete_contractor_confirm_title),
            message = getString(R.string.delete_contractor_confirm_message, contractor.name),
            positiveText = getString(R.string.delete_confirm_yes),
            onPositive = {
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).contractorDao().delete(contractor)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@SelectContractorActivity, getString(R.string.contractor_deleted), Toast.LENGTH_SHORT).show()
                        loadContractors()
                    }
                }
            },
            negativeText = getString(R.string.confirm_cancel)
        )
    }
}
