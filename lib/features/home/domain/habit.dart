import 'package:flutter/material.dart';

import 'date_key.dart';
import 'habit_icons.dart';

class Habit {
  final String id;
  final String title;
  final String scheduledTime;
  final IconData icon;
  final Set<String> completedDates;

  const Habit({
    required this.id,
    required this.title,
    required this.scheduledTime,
    required this.icon,
    this.completedDates = const {},
  });

  bool get isCompletedToday => completedDates.contains(todayKey());

  bool isCompletedOn(String dateKey) => completedDates.contains(dateKey);

  Habit toggleDate(String dateKey) {
    final updated = Set<String>.of(completedDates);
    if (!updated.remove(dateKey)) {
      updated.add(dateKey);
    }
    return copyWith(completedDates: updated);
  }

  Habit copyWith({Set<String>? completedDates}) {
    return Habit(
      id: id,
      title: title,
      scheduledTime: scheduledTime,
      icon: icon,
      completedDates: completedDates ?? this.completedDates,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'scheduledTime': scheduledTime,
      'iconId': habitIconToId(icon),
      'completedDates': completedDates.toList(),
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledTime: json['scheduledTime'] as String,
      icon: habitIconFromId(json['iconId'] as String),
      completedDates: _readCompletedDates(json),
    );
  }

  static Set<String> _readCompletedDates(Map<String, dynamic> json) {
    final rawDates = json['completedDates'];
    if (rawDates is List) {
      return rawDates.map((date) => date as String).toSet();
    }
    if (json['isCompleted'] == true) {
      return {todayKey()};
    }
    return {};
  }
}
