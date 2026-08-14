package com.example.fa_ksiegowy

/**
 * Магазин, из которого установлено приложение (определяется по installer package
 * самой системой Android — см. StoreDetector.kt).
 */
enum class StoreSource {
    GOOGLE_PLAY,
    GALAXY_STORE,
    /** Установлено вручную (adb install, сторонний файловый менеджер и т.п.) — например при разработке через Termux. */
    OTHER
}
