package com.bridgeapp

import android.database.Cursor
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "com.bridgeapp"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getCalendars" -> {
            try {
              result.success(getCalendars())
            } catch (e: Exception) {
              result.error("CALENDAR_ERROR", e.message, null)
            }
          }
          "getEvents" -> {
            try {
              val calendarId = call.argument<String>("calendarId") ?: ""
              val startMillis = call.argument<Long>("startMillis") ?: 0L
              val endMillis = call.argument<Long>("endMillis") ?: 0L
              result.success(getEvents(calendarId, startMillis, endMillis))
            } catch (e: Exception) {
              result.error("CALENDAR_ERROR", e.message, null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun getCalendars(): List<Map<String, Any?>> {
    val projection = arrayOf(
      CalendarContract.Calendars._ID,
      CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
      CalendarContract.Calendars.ACCOUNT_NAME,
      CalendarContract.Calendars.CALENDAR_COLOR
    )

    val calendars = mutableListOf<Map<String, Any?>>()
    val cursor: Cursor? = contentResolver.query(
      CalendarContract.Calendars.CONTENT_URI,
      projection,
      "${CalendarContract.Calendars.VISIBLE} = 1",
      null,
      null
    )

    cursor.use { c ->
      if (c == null) return calendars
      val idxId = c.getColumnIndex(CalendarContract.Calendars._ID)
      val idxName = c.getColumnIndex(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
      val idxAcc = c.getColumnIndex(CalendarContract.Calendars.ACCOUNT_NAME)
      val idxColor = c.getColumnIndex(CalendarContract.Calendars.CALENDAR_COLOR)

      while (c.moveToNext()) {
        calendars.add(
          mapOf(
            "id" to c.getLong(idxId).toString(),
            "name" to (c.getString(idxName) ?: ""),
            "accountName" to (c.getString(idxAcc) ?: ""),
            "color" to if (idxColor >= 0) c.getInt(idxColor) else 0,
            "eventCount" to 0
          )
        )
      }
    }
    return calendars
  }

  private fun getEvents(calendarId: String, startMillis: Long, endMillis: Long): List<Map<String, Any?>> {
    val events = mutableListOf<Map<String, Any?>>()

    val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().apply {
      android.content.ContentUris.appendId(this, startMillis)
      android.content.ContentUris.appendId(this, endMillis)
    }.build()

    val projection = arrayOf(
      CalendarContract.Instances.EVENT_ID,
      CalendarContract.Instances.TITLE,
      CalendarContract.Instances.BEGIN,
      CalendarContract.Instances.END,
      CalendarContract.Instances.ALL_DAY,
      CalendarContract.Instances.EVENT_LOCATION,
      CalendarContract.Instances.DESCRIPTION,
      CalendarContract.Instances.CALENDAR_ID
    )

    val selection = "${CalendarContract.Instances.CALENDAR_ID} = ?"
    val selectionArgs = arrayOf(calendarId)

    val cursor = contentResolver.query(
      uri,
      projection,
      selection,
      selectionArgs,
      "${CalendarContract.Instances.BEGIN} ASC"
    )

    cursor.use { c ->
      if (c == null) return events
      val idxEventId = c.getColumnIndex(CalendarContract.Instances.EVENT_ID)
      val idxTitle = c.getColumnIndex(CalendarContract.Instances.TITLE)
      val idxBegin = c.getColumnIndex(CalendarContract.Instances.BEGIN)
      val idxEnd = c.getColumnIndex(CalendarContract.Instances.END)
      val idxAllDay = c.getColumnIndex(CalendarContract.Instances.ALL_DAY)
      val idxLocation = c.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
      val idxDesc = c.getColumnIndex(CalendarContract.Instances.DESCRIPTION)

      while (c.moveToNext()) {
        events.add(
          mapOf(
            "eventId" to c.getLong(idxEventId).toString(),
            "title" to (c.getString(idxTitle) ?: "(제목 없음)"),
            "start" to c.getLong(idxBegin),
            "end" to c.getLong(idxEnd),
            "allDay" to (c.getInt(idxAllDay) == 1),
            "location" to c.getString(idxLocation),
            "description" to c.getString(idxDesc)
          )
        )
      }
    }
    return events
  }
}
