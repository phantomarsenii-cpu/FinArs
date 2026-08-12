package com.example.fa_ksiegowy

import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

/**
 * Historia powiadomień, otwierana dzwonkiem na ekranie Start — pokazuje wszystkie
 * powiadomienia, ktore aplikacja kiedykolwiek wyslala (limity, faktury, transakcje
 * cykliczne, stany magazynowe), niezaleznie od tego czy zostaly juz usuniete z paska
 * systemowego. Zapisywane przez NotificationLog przy kazdym wywolaniu
 * LimitsNotificationWorker.showNotification.
 */
class NotificationsActivity : BaseActivity() {
    private lateinit var adapter: NotificationAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_notifications)

        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }
        findViewById<TextView>(R.id.tv_clear_all).setOnClickListener {
            NotificationLog.clear(this)
            reload()
        }

        adapter = NotificationAdapter(
            onDelete = { entry ->
                NotificationLog.delete(this, entry.id)
                reload()
            },
            onOpen = { entry -> openTarget(entry) }
        )
        findViewById<RecyclerView>(R.id.rv_notifications).apply {
            layoutManager = LinearLayoutManager(this@NotificationsActivity)
            adapter = this@NotificationsActivity.adapter
        }

        reload()
    }

    override fun onResume() {
        super.onResume()
        reload()
    }

    /** Tap na wpisie w historii powiadomien — otwiera ten sam ekran, ktory
     *  otworzylby tap na systemowym powiadomieniu (patrz NotificationLog.targetClass,
     *  zapisywane przez LimitsNotificationWorker.showNotification). */
    private fun openTarget(entry: NotificationLog.Entry) {
        val className = entry.targetClass ?: return
        try {
            val clazz = Class.forName(className)
            startActivity(android.content.Intent(this, clazz))
        } catch (e: ClassNotFoundException) {
            // Stary wpis z wersji sprzed dodania targetClass — po prostu nic nie robimy.
        }
    }

    private fun reload() {
        val items = NotificationLog.getAll(this)
        adapter.submitList(items)
        findViewById<TextView>(R.id.tv_no_notifications).visibility =
            if (items.isEmpty()) View.VISIBLE else View.GONE
        findViewById<View>(R.id.tv_clear_all).visibility =
            if (items.isEmpty()) View.GONE else View.VISIBLE
    }
}
