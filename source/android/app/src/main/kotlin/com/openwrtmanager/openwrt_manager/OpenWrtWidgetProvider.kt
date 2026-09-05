package com.openwrtmanager.openwrt_manager

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * App Widget Provider для OpenWRT Global.
 *
 * Показывает статус роутера на рабочем столе Android:
 * - Зелёная/красная иконка
 * - Имя роутера
 * - Модель
 * - Uptime
 *
 * Данные сохраняются через home_widget плагин (HomeWidget.saveWidgetData)
 * из Flutter-кода, читаются здесь.
 */
class OpenWrtWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // Получаем сохранённые данные через home_widget плагин.
        val prefs = HomeWidgetPlugin.getData(context)
        val routerName = prefs.getString("router_name", "OpenWRT") ?: "OpenWRT"
        val status = prefs.getString("router_status", "offline") ?: "offline"
        val model = prefs.getString("router_model", "—") ?: "—"
        val uptime = prefs.getString("router_uptime", "—") ?: "—"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.openwrt_widget)
            views.setTextViewText(R.id.widget_router_name, routerName)
            views.setTextViewText(R.id.widget_router_status,
                if (status == "online") "● Online" else "● Offline")
            views.setTextViewText(R.id.widget_router_model, model)
            views.setTextViewText(R.id.widget_router_uptime,
                if (status == "online") "Uptime: $uptime" else "Нет связи")

            // Цвет точки в зависимости от статуса.
            val color = if (status == "online") {
                0xFF22C55E.toInt()  // green
            } else {
                0xFFEF4444.toInt()  // red
            }
            views.setInt(R.id.widget_status_dot, "setColorFilter", color)

            // Тап по виджету → открывает приложение.
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
