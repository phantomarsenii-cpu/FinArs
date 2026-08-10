package com.example.fa_ksiegowy

import android.content.Context
import android.content.Intent
import androidx.appcompat.app.AppCompatActivity

open class BaseActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.applyLocale(newBase))
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
