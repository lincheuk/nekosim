import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'local_notification_service.dart';
import '../utils/profile_tag_utils.dart';
import '../settings/app_settings.dart';
import '../widgets/common/simple_dialog_container.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class ScheduledNotification {
  final String text;
  final DateTime scheduledDate;
  final String iccid;
  final DateTime lastUpdated;
  final String? eid;

  ScheduledNotification({
    required this.text,
    required this.scheduledDate,
    required this.iccid,
    required this.lastUpdated,
    this.eid,
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'scheduledDate': _toMidnight(scheduledDate).millisecondsSinceEpoch,
    'iccid': iccid,
    'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    'eid': eid,
  };

  factory ScheduledNotification.fromMap(Map<String, dynamic> map) =>
      ScheduledNotification(
        text: map['text'] as String,
        scheduledDate: DateTime.fromMillisecondsSinceEpoch(
          map['scheduledDate'] as int,
        ),
        iccid: map['iccid'] as String,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
          map['lastUpdated'] as int,
        ),
        eid: map['eid'] as String?,
      );

  static DateTime _toMidnight(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }
}

class TagNotificationService {
  static final TagNotificationService _instance =
      TagNotificationService._internal();
  factory TagNotificationService() => _instance;
  TagNotificationService._internal();

  static const String _tableName = 'scheduled_notifications';

  /// Hour of day (local) at which date reminders fire.
  static const int _fireHour = 9;

  Future<void> upsertNotification(ScheduledNotification notif) async {
    final db = await DatabaseService().database;
    await db.insert(
      _tableName,
      notif.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _syncOsSchedule(notif);
  }

  Future<void> deleteNotification(String text, DateTime date) async {
    final db = await DatabaseService().database;
    final midnight = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    await db.delete(
      _tableName,
      where: 'text = ? AND scheduledDate = ?',
      whereArgs: [text, midnight],
    );
    await LocalNotificationService()
        .cancelReminder(LocalNotificationService.reminderId(text, date));
  }

  /// Mirror a stored reminder into an OS-level zonedSchedule alarm.
  /// Fires at [_fireHour] local on the scheduled day; if that moment has
  /// already passed but the day has not, fires shortly after now.
  Future<void> _syncOsSchedule(ScheduledNotification notif) async {
    if (!AppSettings().enableScheduledNotifications) return;
    final d = notif.scheduledDate;
    var when = DateTime(d.year, d.month, d.day, _fireHour);
    final now = DateTime.now();
    if (!when.isAfter(now)) {
      final endOfDay = DateTime(d.year, d.month, d.day, 23, 59, 59);
      if (!endOfDay.isAfter(now)) return; // day already over
      when = now.add(const Duration(minutes: 2));
    }
    final id = LocalNotificationService.reminderId(notif.text, d);
    final svc = LocalNotificationService();
    await svc.cancelReminder(id);
    await svc.scheduleReminder(
      id: id,
      title: notif.text,
      body: DateFormat('yyyy-MM-dd').format(d),
      when: when,
      payload: jsonEncode({'iccid': notif.iccid, 'eid': notif.eid ?? ''}),
    );
  }

  /// Re-arm OS alarms for every stored future reminder. Called at startup:
  /// covers app updates, reinstalls-with-backup and rows created before
  /// OS scheduling existed.
  Future<void> rescheduleAllPending() async {
    if (!AppSettings().enableScheduledNotifications) return;
    try {
      final all = await getAllNotifications();
      for (final n in all) {
        await _syncOsSchedule(n);
      }
    } catch (e) {
      debugPrint('rescheduleAllPending failed: $e');
    }
  }

  Future<ScheduledNotification?> getNotification(
    String text,
    DateTime date,
  ) async {
    final db = await DatabaseService().database;
    final midnight = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final results = await db.query(
      _tableName,
      where: 'text = ? AND scheduledDate = ?',
      whereArgs: [text, midnight],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return ScheduledNotification.fromMap(results.first);
  }

  Future<List<ScheduledNotification>> getAllNotifications() async {
    final db = await DatabaseService().database;
    final results = await db.query(_tableName, orderBy: 'scheduledDate ASC');
    return results.map((m) => ScheduledNotification.fromMap(m)).toList();
  }

  Future<void> promptAndSchedule(
    BuildContext context,
    String iccid,
    DateTag tag, {
    String? profileName,
    String? profileNickname,
    String? regionCode,
  }) async {
    if (!AppSettings().enableScheduledNotifications) return;

    final tagLabel = tag.note ?? tag.raw;
    final existing = await getNotification(tagLabel, tag.date);
    if (existing != null) return; // Already scheduled for this text/date

    if (!context.mounted) return;

    // Use cleaned nickname (without tags) or fallback to name
    String profileInfo = "";
    if (profileNickname != null && profileNickname.isNotEmpty) {
      final cleanedNickname = ProfileTagUtils.parse(
        profileNickname,
        regionCode: regionCode,
      ).displayName;
      if (cleanedNickname.isNotEmpty) {
        profileInfo = " for $cleanedNickname";
      }
    }
    if (profileInfo.isEmpty && profileName != null && profileName.isNotEmpty) {
      profileInfo = " for $profileName";
    }

    // Display raw tag in quotes if no note
    final displayTag = tag.note ?? '"${tag.raw}"';

    final confirmed = await _showPrompt(
      context,
      "Schedule Reminder",
      "Would you like to schedule a notification for $displayTag$profileInfo on ${DateFormat('yyyy-MM-dd').format(tag.date.toLocal())}?",
    );

    if (confirmed == true) {
      if (context.mounted) {
        await _ensurePermissions(context);
      }

      await upsertNotification(
        ScheduledNotification(
          text: tagLabel,
          scheduledDate: tag.date,
          iccid: iccid,
          lastUpdated: DateTime.now(),
        ),
      );
    }
  }

  Future<void> promptAndReschedule(
    BuildContext context,
    String iccid,
    DateTag? oldTag,
    DateTag newTag, {
    String? profileName,
    String? profileNickname,
    String? regionCode,
  }) async {
    if (!AppSettings().enableScheduledNotifications) return;
    if (oldTag != null && oldTag.raw == newTag.raw) return;

    // Only prompt if there are scheduled ones for the old tag (per requirement)
    final oldTagLabel = oldTag?.note ?? oldTag?.raw ?? "Expiry";
    final existingOld = oldTag != null
        ? await getNotification(oldTagLabel, oldTag.date)
        : null;

    if (existingOld == null) {
      // If no old one, just offer to schedule the new one
      if (context.mounted) {
        await promptAndSchedule(
          context,
          iccid,
          newTag,
          profileName: profileName,
          profileNickname: profileNickname,
          regionCode: regionCode,
        );
      }
      return;
    }

    if (!context.mounted) return;

    // Use cleaned nickname (without tags) or fallback to name
    String profileInfo = "";
    if (profileNickname != null && profileNickname.isNotEmpty) {
      final cleanedNickname = ProfileTagUtils.parse(
        profileNickname,
        regionCode: regionCode,
      ).displayName;
      if (cleanedNickname.isNotEmpty) {
        profileInfo = " for $cleanedNickname";
      }
    }
    if (profileInfo.isEmpty && profileName != null && profileName.isNotEmpty) {
      profileInfo = " for $profileName";
    }

    // Display raw tag in quotes if no note
    final displayTag = newTag.note ?? '"${newTag.raw}"';
    final newTagLabel = newTag.note ?? newTag.raw;

    final confirmed = await _showPrompt(
      context,
      "Update Reminder",
      "The date tag has changed to $displayTag (${DateFormat('yyyy-MM-dd').format(newTag.date.toLocal())})$profileInfo. Would you like to update your scheduled reminder?",
    );

    if (confirmed == true) {
      if (context.mounted) {
        await _ensurePermissions(context);
      }

      await deleteNotification(oldTagLabel, oldTag!.date);
      await upsertNotification(
        ScheduledNotification(
          text: newTagLabel,
          scheduledDate: newTag.date,
          iccid: iccid,
          lastUpdated: DateTime.now(),
        ),
      );
    }
  }

  Future<void> promptAndRemove(
    BuildContext context,
    String iccid,
    DateTag tag, {
    String? profileName,
    String? profileNickname,
    String? regionCode,
  }) async {
    if (!AppSettings().enableScheduledNotifications) return;

    final tagLabel = tag.note ?? tag.raw;
    final existing = await getNotification(tagLabel, tag.date);
    if (existing == null) return;

    if (!context.mounted) return;

    // Use cleaned nickname (without tags) or fallback to name
    String profileInfo = "";
    if (profileNickname != null && profileNickname.isNotEmpty) {
      final cleanedNickname = ProfileTagUtils.parse(
        profileNickname,
        regionCode: regionCode,
      ).displayName;
      if (cleanedNickname.isNotEmpty) {
        profileInfo = " for $cleanedNickname";
      }
    }
    if (profileInfo.isEmpty && profileName != null && profileName.isNotEmpty) {
      profileInfo = " for $profileName";
    }

    // Display raw tag in quotes if no note
    final displayTag = tag.note ?? '"${tag.raw}"';

    final confirmed = await _showPrompt(
      context,
      "Remove Reminder",
      "The date tag $displayTag$profileInfo was removed. Would you like to also remove the scheduled notification?",
    );

    if (confirmed == true) {
      await deleteNotification(tagLabel, tag.date);
    }
  }

  Future<void> _ensurePermissions(BuildContext context) async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "Refused permissions to schedule notification.",
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              action: SnackBarAction(
                label: "Settings",
                onPressed: () => openAppSettings(),
                textColor: Colors.white,
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Silently ignore on unsupported platforms (Linux/macOS)
      debugPrint("Permission check not supported or failed: $e");
    }
  }

  Future<bool?> _showPrompt(
    BuildContext context,
    String title,
    String message,
  ) async {
    return await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return SimpleDialogContainer(
          title: title,
          primaryActionLabel: "Yes",
          secondaryActionLabel: "No",
          onPrimaryAction: () => Navigator.pop(context, true),
          onSecondaryAction: () => Navigator.pop(context, false),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.onSurfaceSubtle(context),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
