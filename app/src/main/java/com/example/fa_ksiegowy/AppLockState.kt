package com.example.fa_ksiegowy

import android.content.Context

/**
 * Отслеживает, сколько Activity сейчас "запущено" (started), чтобы понять,
 * когда приложение целиком уходит в фон и когда возвращается на передний план.
 * Как только счётчик переходит с 0 на 1 (приложение снова видно пользователю)
 * и PIN установлен — выставляем isLocked = true, и BaseActivity показывает
 * LockActivity поверх текущего экрана. Успешный ввод PIN/биометрии сбрасывает
 * isLocked обратно в false до следующего полного ухода в фон.
 */
object AppLockState {

    @Volatile
    var isLocked: Boolean = false
        internal set

    private var startedActivityCount = 0

    fun onActivityStarted(context: Context) {
        if (startedActivityCount == 0 && SecurityHelper.hasPin(context)) {
            isLocked = true
        }
        startedActivityCount++
    }

    fun onActivityStopped() {
        if (startedActivityCount > 0) startedActivityCount--
    }

    fun unlock() {
        isLocked = false
    }
}
