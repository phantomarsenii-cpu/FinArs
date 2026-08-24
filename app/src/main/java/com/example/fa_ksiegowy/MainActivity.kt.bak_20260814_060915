package com.example.fa_ksiegowy

import android.os.Bundle

/**
 * Постоянный хост для главной вкладки ("Start"). Заменяет собой бывший MineActivity —
 * все прежние ссылки на MineActivity (лаунчер, уведомления, TermsActivity,
 * SettingsLanguageActivity) теперь указывают сюда.
 *
 * Update: этап 1 миграции на единый Activity-хост с фрагментами — цель в том, чтобы
 * нижняя навигация и рекламный баннер создавались ОДИН РАЗ за всё время жизни этой
 * Activity и не пересоздавались/не перезагружались при переключении вкладок (раньше
 * каждая вкладка была отдельной Activity, и AdView грузился заново при каждом переходе).
 *
 * Пока фрагментом стал только "Start" (MineFragment). Magazyn/Raporty/Ustawienia
 * по-прежнему отдельные Activity — переключение на них по-старому запускает Activity
 * (см. BottomNavBar.attachHost). Они будут переведены на фрагменты на следующих этапах;
 * тогда переключение между ВСЕМИ вкладками перестанет пересоздавать баннер/нав-бар.
 */
class MainActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .replace(R.id.fragment_container, MineFragment(), TAG_MINE)
                .commit()
        }

        // onStartSelected не используется на этом этапе: пока внутри MainActivity
        // существует только вкладка Start, current всегда Tab.START — задел на будущее,
        // когда Magazyn/Raporty/Ustawienia тоже станут фрагментами этого же хоста.
        BottomNavBar.attachHost(this, BottomNavBar.Tab.START) { }
    }

    companion object {
        private const val TAG_MINE = "mine_fragment"
    }
}
