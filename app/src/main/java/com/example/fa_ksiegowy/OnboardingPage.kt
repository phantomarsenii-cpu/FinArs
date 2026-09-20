package com.example.fa_ksiegowy

import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes

/**
 * Одна карточка онбординга: иконка (в цветном круге), заголовок и описание.
 * Тексты подтягиваются из строковых ресурсов, чтобы работать на всех трёх
 * языках интерфейса (en/pl/ru) — см. R.string.onboarding_*.
 */
data class OnboardingPage(
    @DrawableRes val iconRes: Int,
    @ColorRes val iconBgColor: Int,
    @StringRes val titleRes: Int,
    @StringRes val descriptionRes: Int
)
