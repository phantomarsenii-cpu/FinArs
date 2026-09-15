package com.example.fa_ksiegowy

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity

open class BaseActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.applyLocale(newBase))
    }

    // Приложение показывает финансовые данные (баланс, PIN, документы) на КАЖДОМ
    // экране — все они наследуются от BaseActivity, поэтому проще и надёжнее
    // закрыть весь app целиком, чем помечать экраны по отдельности. FLAG_SECURE
    // запрещает скриншоты/запись экрана и скрывает содержимое в списке недавних
    // приложений (Recents), не влияя ни на что другое в работе приложения.
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    // Update: pelny ekran "jak w Revolut" — tresc pod paskiem statusu i pod
    // dolnym paskiem nawigacji systemowej, z realnym rozmyciem tego, co tam
    // wjezdza (patrz EdgeToEdge.kt). onContentChanged() wywoluje sie
    // automatycznie zaraz PO kazdym setContentView() — dzieki temu dziala to
    // na KAZDYM ekranie apki (kazda Activity dziedziczy z BaseActivity),
    // bez potrzeby wywolywania czegokolwiek recznie w kazdej z osobna.
    override fun onContentChanged() {
        super.onContentChanged()
        EdgeToEdge.apply(this)
    }

    // Ladny fade+scale zamiast domyslnego "slajdu" systemowego przy przejsciu
    // miedzy ekranami — dotyczy KAZDEGO startActivity() w calej aplikacji,
    // bo wszystkie ekrany dziedzicza z BaseActivity.
    override fun startActivity(intent: Intent) {
        super.startActivity(intent)
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    override fun startActivity(intent: Intent, options: android.os.Bundle?) {
        super.startActivity(intent, options)
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    /** Показываем экран блокировки поверх любого экрана приложения, если
     *  AppLockState считает, что приложение только что вернулось из фона
     *  и PIN установлен. Сам LockActivity этот код у себя не выполняет
     *  (иначе он бесконечно запускал бы сам себя).
     *
     *  Перед этим проверяем, принято ли пользовательское соглашение —
     *  если нет, перехватываем навигацию и открываем TermsActivity
     *  (кроме самого TermsActivity, чтобы не зациклиться). */
    override fun onResume() {
        super.onResume()
        if (this !is TermsActivity && !TermsActivity.isAccepted(this)) {
            startActivity(Intent(this, TermsActivity::class.java))
            return
        }
        if (this !is LockActivity && AppLockState.isLocked) {
            startActivity(Intent(this, LockActivity::class.java))
        }
    }
}
