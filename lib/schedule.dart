/// Расписание: дни недели (бит 0 = понедельник) и окно «с — до» в минутах от полуночи.
/// Если «до» не позже «с», окно идёт через полночь и принадлежит дню начала.
class Schedule {
  const Schedule({this.enabled = false, this.days = 0x1F, this.start = 9 * 60, this.end = 18 * 60});

  final bool enabled;
  final int days, start, end;

  bool get overnight => end <= start;

  bool hasDay(int weekday) => days & (1 << (weekday - 1)) != 0;

  Schedule copyWith({bool? enabled, int? days, int? start, int? end}) => Schedule(
    enabled: enabled ?? this.enabled,
    days: days ?? this.days,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  /// Конец текущего окна, если [now] внутри него; иначе null.
  DateTime? windowEnd(DateTime now) {
    if (!enabled || days == 0) return null;
    final today = DateTime(now.year, now.month, now.day);
    // окно, начавшееся вчера (через полночь), или сегодняшнее
    for (final day in [today.subtract(const Duration(days: 1)), today]) {
      if (!hasDay(day.weekday)) continue;
      final from = _at(day, start);
      final to = _at(overnight ? day.add(const Duration(days: 1)) : day, end);
      if (!now.isBefore(from) && now.isBefore(to)) return to;
    }
    return null;
  }

  // Через DateTime(y, m, d, h, m), а не add(minutes): переход на летнее время не сдвигает окно.
  static DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  Map<String, Object> toJson() => {'enabled': enabled, 'days': days, 'start': start, 'end': end};

  static Schedule fromJson(Object? j) {
    if (j is! Map) return const Schedule();
    int minutes(Object? v, int def) => v is int && v >= 0 && v < 24 * 60 ? v : def;
    return Schedule(
      enabled: j['enabled'] == true,
      days: j['days'] is int ? (j['days'] as int) & 0x7F : 0x1F,
      start: minutes(j['start'], 9 * 60),
      end: minutes(j['end'], 18 * 60),
    );
  }
}

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
String minutesToHhmm(int m) => '${two(m ~/ 60)}:${two(m % 60)}';
String two(int v) => v.toString().padLeft(2, '0');
