import 'package:flutter/material.dart';

/// Parses a time formatted as `hh:mm AM/PM` (the format produced by the
/// habit creation form). Returns null if [value] doesn't match that format.
TimeOfDay? parseScheduledTime(String value) {
  try {
    final parts = value.split(' ');
    final hourMinute = parts[0].split(':');
    var hour = int.parse(hourMinute[0]) % 12;
    if (parts[1] == 'PM') hour += 12;
    return TimeOfDay(hour: hour, minute: int.parse(hourMinute[1]));
  } catch (_) {
    return null;
  }
}
