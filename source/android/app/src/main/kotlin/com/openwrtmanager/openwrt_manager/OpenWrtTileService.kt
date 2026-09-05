package com.openwrtmanager.openwrt_manager

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings Tile для OpenWRT Global (Android 7.0+).
 *
 * Показывает статус роутера прямо в шторке Android:
 * - 🟢 Зелёная подсветка иконки — роутер онлайн
 * - 🔴 Красная подсветка — оффлайн
 * - Тап → открывает приложение
 *
 * Статус читается из home_widget данных, которые обновляет
 * RouterMonitorService из Flutter-кода.
 */
@RequiresApi(Build.VERSION_CODES.N)
class OpenWrtTileService : TileService() {

    companion object {
        /** Цвет активного состояния (онлайн) — зелёный. */
        const val COLOR_ONLINE = 0xFF22C55E.toInt()
        /** Цвет неактивного состояния (оффлайн) — красный. */
        const val COLOR_OFFLINE = 0xFFEF4444.toInt()
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        // Тап → открывает приложение.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivityAndCollapse(launchIntent)
            } catch (e: Exception) {
                startActivity(launchIntent)
            }
        }
    }

    /**
     * Обновляет внешний вид плитки на основе статуса роутера.
     * Дёргается из RouterMonitorService через saveWidgetData +
     * HomeWidget.updateWidget, либо напрямую читает SharedPreferences
     * с именем "flutter.router_status" (значения "online"/"offline").
     */
    private fun updateTile() {
        val tile = qsTile ?: return

        // Пробуем прочитать статус из home_widget (flutter).
        val prefs = try {
            getSharedPreferences("home_widget_prefs", MODE_PRIVATE)
        } catch (_: Exception) {
            null
        }
        val status = prefs?.getString("flutter.router_status", "offline") ?: "offline"
        val isOnline = status == "online"

        // Цвет иконки: зелёный/красный.
        val color = if (isOnline) COLOR_ONLINE else COLOR_OFFLINE

        // Используем разные иконки: зелёный круг (онлайн) / красный круг (оффлайн).
        // На Android 13+ дополнительно применяем tint.
        val iconRes = if (isOnline) R.drawable.ic_tile_online else R.drawable.ic_tile_offline
        val icon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Icon.createWithResource(this, iconRes).setTint(color)
        } else {
            Icon.createWithResource(this, iconRes)
        }

        tile.label = getString(R.string.qs_tile_label)
        tile.icon = icon
        tile.state = if (isOnline) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE

        // Подсветка плитки (доступна с Android 13+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                // Если TileService в режиме QS panel, подсветка активной плитки
                // определяется автоматически. Дополнительно — устанавливаем contentDescription.
                tile.contentDescription = if (isOnline) {
                    "OpenWRT — роутер онлайн"
                } else {
                    "OpenWRT — роутер оффлайн"
                }
            } catch (_: Exception) {
                // ignore
            }
        } else {
            tile.contentDescription = if (isOnline) {
                "OpenWRT: Online"
            } else {
                "OpenWRT: Offline"
            }
        }

        tile.updateTile()
    }
}
