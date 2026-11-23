package cz.gleba.gleba

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
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
        } else {
          views.setViewVisibility(rows[i], View.GONE)
        }
      }

      views.setOnClickPendingIntent(
          R.id.root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("gleba://open")),
      )
      views.setOnClickPendingIntent(
          R.id.add,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("gleba://add")),
      )
      appWidgetManager.updateAppWidget(id, views)
    }
  }
}
