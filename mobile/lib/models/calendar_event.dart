import 'package:flutter/material.dart';

enum CalendarCategory { shipping, receiving, report, approval, milestone }

extension CalendarCategoryX on CalendarCategory {
  String get label {
    switch (this) {
      case CalendarCategory.shipping:
        return '출하';
      case CalendarCategory.receiving:
        return '입고';
      case CalendarCategory.report:
        return '보고';
      case CalendarCategory.approval:
        return '승인·검토';
      case CalendarCategory.milestone:
        return '마일스톤';
    }
  }

  Color get color {
    switch (this) {
      case CalendarCategory.shipping:
        return const Color(0xFFE53935);
      case CalendarCategory.receiving:
        return const Color(0xFF1E88E5);
      case CalendarCategory.report:
        return const Color(0xFF43A047);
      case CalendarCategory.approval:
        return const Color(0xFF8E24AA);
      case CalendarCategory.milestone:
        return const Color(0xFFFB8C00);
    }
  }
}

class CalendarEvent {
  final String id;
  final DateTime date;
  final CalendarCategory category;
  final String title;
  final String divisionLabel;
  final String projectLabel;
  final String? time;
  final bool isDone;
  final String projectKey;
  final String headline;

  const CalendarEvent({
    required this.id,
    required this.date,
    required this.category,
    required this.title,
    required this.divisionLabel,
    required this.projectLabel,
    this.time,
    this.isDone = false,
    this.projectKey = '',
    this.headline = '',
  });

  CalendarEvent copyWith({bool? isDone}) => CalendarEvent(
        id: id,
        date: date,
        category: category,
        title: title,
        divisionLabel: divisionLabel,
        projectLabel: projectLabel,
        time: time,
        isDone: isDone ?? this.isDone,
        projectKey: projectKey,
        headline: headline,
      );

  int diffDays(DateTime today) {
    final d0 = DateTime(today.year, today.month, today.day);
    final d1 = DateTime(date.year, date.month, date.day);
    return d1.difference(d0).inDays;
  }
}
