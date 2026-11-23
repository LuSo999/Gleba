package cz.gleba.gleba

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import org.json.JSONArray

/**
 * Home-screen widget: the items that expire first.
 *
 * The app saves, for each item, its labels and colours for the next 8 days
 * ("zítra", "dnes", "prošlo včera"…) together with the date they start from,
 * so the widget stays correct day after day even when the app isn't opened.
 */
class GlebaWidgetProvider : HomeWidgetProvider() {
  private val rows = intArrayOf(R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
  private val names = intArrayOf(R.id.name1, R.id.name2, R.id.name3, R.id.name4, R.id.name5)
  private val whens = intArrayOf(R.id.when1, R.id.when2, R.id.when3, R.id.when4, R.id.when5)
  private val takes = intArrayOf(R.id.take1, R.id.take2, R.id.take3, R.id.take4, R.id.take5)

  private fun open(context: Context, uri: String) =
      HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

  /** Runs Dart in the background (widgetInteraction in widget_actions.dart) without opening the app. */
  private fun background(context: Context, uri: String) =
      HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri))

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val items = try {
      JSONArray(widgetData.getString("items", "[]"))
    } catch (e: Exception) {
      JSONArray()
    }
    val offset = widgetData.getString("base", null)?.let {
      try {
        ChronoUnit.DAYS.between(LocalDate.parse(it), LocalDate.now()).toInt()
      } catch (e: Exception) {
        0
      }
    } ?: 0

    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.gleba_widget)
      views.setTextViewText(R.id.title, widgetData.getString("title", "Gleba"))
      views.setTextViewText(R.id.empty, widgetData.getString("empty", ""))
      views.setViewVisibility(R.id.empty, if (items.length() == 0) View.VISIBLE else View.GONE)

      for (i in rows.indices) {
        if (i < items.length()) {
          val item = items.getJSONObject(i)
          val labels = item.getJSONArray("r")
          val colors = item.getJSONArray("c")
          val day = offset.coerceIn(0, labels.length() - 1)
          views.setViewVisibility(rows[i], View.VISIBLE)
          views.setTextViewText(names[i], item.getString("e") + "  " + item.getString("n"))
          views.setTextViewText(whens[i], labels.getString(day))
          views.setTextColor(whens[i], colors.getLong(day).toInt())
          val ref = "h=" + Uri.encode(item.getString("h")) + "&i=" + Uri.encode(item.getString("i"))
          views.setTextViewText(takes[i], if (item.optBoolean("m")) "−1" else "✓")
          views.setOnClickPendingIntent(takes[i], background(context, "gleba://take?$ref"))
          views.setOnClickPendingIntent(rows[i], open(context, "gleba://item?$ref"))
        } else {
          views.setViewVisibility(rows[i], View.GONE)
        }
      }

      // Last action from the widget, with undo, for 15 minutes.
      // Stored as a string: the plugin saves small Dart ints as Int, big ones as Long.
      val lastAt = widgetData.getString("lastAt", null)?.toLongOrNull() ?: 0L
      val showLast = lastAt > 0 && System.currentTimeMillis() - lastAt < 15 * 60 * 1000
      views.setViewVisibility(R.id.lastRow, if (showLast) View.VISIBLE else View.GONE)
      views.setTextViewText(R.id.lastText, widgetData.getString("lastText", ""))
      views.setTextViewText(R.id.undo, widgetData.getString("undoLabel", "Undo"))
      views.setOnClickPendingIntent(R.id.undo, background(context, "gleba://undo"))

      views.setTextViewText(R.id.take, "🍽 " + widgetData.getString("takeLabel", "Take"))
      views.setOnClickPendingIntent(R.id.root, open(context, "gleba://open"))
      views.setOnClickPendingIntent(R.id.take, open(context, "gleba://take-search"))
      views.setOnClickPendingIntent(R.id.add, open(context, "gleba://add"))
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}
