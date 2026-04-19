import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:nrf/data/ble_data_model.dart';
import 'package:nrf/data/database_helper.dart';
import 'package:nrf/shared/ui_components.dart';
import 'package:nrf/shared/ui_constants.dart';

enum _SleepStage { none, awake, rem, light, deep }
enum _AnalysisRange { minute, hour }

class _SleepSegment {
  final double startHour;
  final double endHour;
  final _SleepStage stage;

  const _SleepSegment({
    required this.startHour,
    required this.endHour,
    required this.stage,
  });
}

class DataScreen extends StatefulWidget {
  final DiscoveredDevice? device;

  const DataScreen({super.key, required this.device});

  @override
  DataScreenState createState() => DataScreenState();
}

class DataScreenState extends State<DataScreen> {
  List<BleData> _history = [];
  bool _isLoading = true;
  _AnalysisRange _selectedRange = _AnalysisRange.minute;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper().getBleData(limit: 500);
      if (mounted) {
        setState(() {
          _history = data.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chartData = _chartData;

    return Scaffold(
      backgroundColor: kScreenBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : chartData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('선택한 범위의 데이터가 없습니다'),
                        TextButton.icon(
                          onPressed: loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: kScreenPadding,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildRangeFilter(),
                          const SizedBox(height: 24),
                          _TrendChart(
                            spots: _getSpots(chartData, (d) => d.hr),
                            timestamps: chartData.map((d) => d.timestamp).toList(),
                            range: _selectedRange,
                            color: Colors.red,
                            title: 'Heart Rate (bpm)',
                            minY: 40,
                            maxY: 180,
                          ),
                          const SizedBox(height: 32),
                          _TrendChart(
                            spots: _getSpots(chartData, (d) => d.spo2),
                            timestamps: chartData.map((d) => d.timestamp).toList(),
                            range: _selectedRange,
                            color: Colors.blue,
                            title: 'SpO₂ (%)',
                            minY: 0,
                            maxY: 100,
                          ),
                          const SizedBox(height: 32),
                          _TrendChart(
                            spots: _getSpots(chartData, (d) => d.stress),
                            timestamps: chartData.map((d) => d.timestamp).toList(),
                            range: _selectedRange,
                            color: Colors.orange,
                            title: 'Stress Level',
                            minY: 0,
                            maxY: 100,
                          ),
                          const SizedBox(height: 32),
                          _SleepChart(source: _history),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  List<BleData> get _chartData {
    if (_history.isEmpty) return const [];

    final sorted = [..._history]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return switch (_selectedRange) {
      _AnalysisRange.minute => sorted.takeLast(30),
      _AnalysisRange.hour => _aggregateByHour(sorted).takeLast(24),
    };
  }

  List<FlSpot> _getSpots(List<BleData> source, num Function(BleData) getValue) {
    return List.generate(source.length, (i) {
      return FlSpot(i.toDouble(), getValue(source[i]).toDouble());
    });
  }

  List<BleData> _aggregateByHour(List<BleData> source) {
    final buckets = <DateTime, List<BleData>>{};

    for (final item in source) {
      final key = DateTime(
        item.timestamp.year,
        item.timestamp.month,
        item.timestamp.day,
        item.timestamp.hour,
      );
      buckets.putIfAbsent(key, () => []).add(item);
    }

    return buckets.entries.map((entry) => _averageBucket(entry.key, entry.value)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  BleData _averageBucket(DateTime timestamp, List<BleData> bucket) {
    int avg(num Function(BleData) getValue) {
      final sum = bucket.fold<num>(0, (total, item) => total + getValue(item));
      return (sum / bucket.length).round();
    }

    return BleData(
      timestamp: timestamp,
      type: BleDataType.unknown,
      hr: avg((d) => d.hr),
      rr: avg((d) => d.rr),
      spo2: avg((d) => d.spo2),
      sdnn: avg((d) => d.sdnn),
      rmssd: avg((d) => d.rmssd),
      stress: avg((d) => d.stress),
      sleep: BleSleepType.none,
    );
  }

  Widget _buildRangeFilter() {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRangeButton(label: '분', range: _AnalysisRange.minute),
          const SizedBox(width: 6),
          _buildRangeButton(label: '시간', range: _AnalysisRange.hour),
        ],
      ),
    );
  }

  Widget _buildRangeButton({
    required String label,
    required _AnalysisRange range,
  }) {
    final isSelected = _selectedRange == range;

    return GestureDetector(
      onTap: () => setState(() => _selectedRange = range),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF111111) : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

extension on List<BleData> {
  List<BleData> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}

class _SleepChart extends StatelessWidget {
  final List<BleData> source;

  const _SleepChart({
    required this.source,
  });

  static const List<String> _rowLabels = ['뒤척임', 'REM 수면', '얕은 수면', '깊은 수면'];

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimelineData(source);
    final date = timeline.date;
    final dateText = date == null
        ? '수면 데이터 없음'
        : '${date.year}년 ${date.month}월 ${date.day}일';
    final totalMinutes = timeline.summary.inMinutes;
    final hourText = '${totalMinutes ~/ 60}';
    final minuteText = '${totalMinutes % 60}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle(title: '수면'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '수면 시간',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.black),
                              children: [
                                TextSpan(
                                  text: hourText,
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                                ),
                                const TextSpan(
                                  text: '시간 ',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: minuteText,
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                                ),
                                const TextSpan(
                                  text: '분',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.info_outline, size: 18, color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const labelWidth = 64.0;
                      const bottomLabelHeight = 28.0;
                      final chartWidth = constraints.maxWidth - labelWidth;
                      final chartHeight = constraints.maxHeight - bottomLabelHeight;
                      const rowCount = 4;
                      final rowHeight = chartHeight / rowCount;

                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            width: labelWidth,
                            height: chartHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: List.generate(rowCount, (index) {
                                return SizedBox(
                                  height: rowHeight,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _rowLabels[index],
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          Positioned(
                            left: labelWidth,
                            top: 0,
                            width: chartWidth,
                            height: chartHeight,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size(chartWidth, chartHeight),
                                  painter: _SleepChartGridPainter(
                                    timeLabels: timeline.timeLabels,
                                    timelineHours: timeline.timelineHours,
                                  ),
                                ),
                                CustomPaint(
                                  size: Size(chartWidth, chartHeight),
                                  painter: _SleepConnectorPainter(
                                    segments: timeline.segments,
                                    timelineHours: timeline.timelineHours,
                                  ),
                                ),
                                ...timeline.segments.map(
                                  (segment) => _buildSleepSegment(
                                    segment: segment,
                                    chartWidth: chartWidth,
                                    rowHeight: rowHeight,
                                    timelineHours: timeline.timelineHours,
                                  ),
                                ),
                                if (timeline.segments.isEmpty)
                                  Center(
                                    child: Text(
                                      '수면 데이터가 없습니다',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: labelWidth,
                            bottom: 0,
                            width: chartWidth,
                            height: bottomLabelHeight,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: timeline.timeLabels
                                  .map(
                                    (label) => Positioned(
                                      left: _sleepChartXForHour(label.hour, chartWidth, timeline.timelineHours),
                                      child: Transform.translate(
                                        offset: const Offset(-4, 0),
                                        child: Text(
                                          label.label,
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
        ),
      ],
    );
  }

  _SleepTimelineData _buildTimelineData(List<BleData> data) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final todayEntries = data
        .where((item) => !item.timestamp.isBefore(dayStart) && item.timestamp.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (todayEntries.isEmpty) {
      return _SleepTimelineData(
        segments: [],
        timeLabels: _buildTimeLabels(dayStart, 6),
        timelineHours: 6,
        summary: Duration.zero,
        date: dayStart,
      );
    }

    final minuteSleepEntries = todayEntries
        .where((item) => item.type == BleDataType.minute)
        .toList();
    final sleepEntries = minuteSleepEntries.isNotEmpty ? minuteSleepEntries : todayEntries;
    final firstSleepEntry = sleepEntries.cast<BleData?>().firstWhere(
      (item) => item != null && item.sleep != BleSleepType.none && item.sleep != BleSleepType.unknown,
      orElse: () => null,
    );
    final timelineStart = firstSleepEntry?.timestamp ?? sleepEntries.first.timestamp;
    final timelineEntries = sleepEntries
        .where((item) => !item.timestamp.isBefore(timelineStart))
        .toList();
    final timelineEnd = timelineEntries.isNotEmpty
        ? timelineEntries.last.timestamp.add(const Duration(minutes: 1))
        : timelineStart.add(const Duration(hours: 6));
    final timelineHours =
        (timelineEnd.difference(timelineStart).inMinutes / 60.0).clamp(3.0, 18.0);
    final segments = _buildSegments(timelineEntries, timelineStart, timelineHours);
    final summary = _calculateSleepSummary(sleepEntries, dayEnd);

    return _SleepTimelineData(
      segments: segments,
      timeLabels: _buildTimeLabels(timelineStart, timelineHours),
      timelineHours: timelineHours,
      summary: summary,
      date: timelineStart,
    );
  }

  Duration _calculateSleepSummary(List<BleData> entries, DateTime dayEnd) {
    if (entries.isEmpty) return Duration.zero;

    final minuteEntries = entries.where((item) => item.type == BleDataType.minute).toList();
    if (minuteEntries.isNotEmpty) {
      final sleepMinutes = minuteEntries.where((item) {
        return switch (item.sleep) {
          BleSleepType.awake || BleSleepType.light || BleSleepType.deep || BleSleepType.rem => true,
          _ => false,
        };
      }).length;
      return Duration(minutes: sleepMinutes);
    }

    return entries.asMap().entries.fold<Duration>(
      Duration.zero,
      (total, entry) {
        final index = entry.key;
        final item = entry.value;
        final nextTime = index < entries.length - 1 ? entries[index + 1].timestamp : dayEnd;
        final gapMinutes = nextTime.difference(item.timestamp).inMinutes.clamp(0, 60);
        final duration = Duration(minutes: gapMinutes == 0 ? 1 : gapMinutes);

        return switch (item.sleep) {
          BleSleepType.awake || BleSleepType.light || BleSleepType.deep || BleSleepType.rem => total + duration,
          _ => total,
        };
      },
    );
  }

  List<_SleepSegment> _buildSegments(
    List<BleData> session,
    DateTime timelineStart,
    double timelineHours,
  ) {
    if (session.isEmpty) return const [];

    final segments = <_SleepSegment>[];
    var segmentStart = session.first.timestamp;
    var currentSleep = session.first.sleep;

    for (var i = 1; i < session.length; i++) {
      final item = session[i];
      final gap = item.timestamp.difference(session[i - 1].timestamp).inMinutes;

      if (item.sleep != currentSleep || gap > 30) {
        segments.add(
          _SleepSegment(
            startHour: _sleepHourFromStart(segmentStart, timelineStart, timelineHours),
            endHour: _sleepHourFromStart(
              session[i - 1].timestamp.add(const Duration(minutes: 1)),
              timelineStart,
              timelineHours,
            ),
            stage: _toStage(currentSleep),
          ),
        );
        segmentStart = item.timestamp;
        currentSleep = item.sleep;
      }
    }

    segments.add(
      _SleepSegment(
        startHour: _sleepHourFromStart(segmentStart, timelineStart, timelineHours),
        endHour: _sleepHourFromStart(
          session.last.timestamp.add(const Duration(minutes: 1)),
          timelineStart,
          timelineHours,
        ),
        stage: _toStage(currentSleep),
      ),
    );

    return segments.where((segment) => segment.stage != _SleepStage.none).toList();
  }

  double _sleepHourFromStart(DateTime time, DateTime start, double timelineHours) {
    final hour = time.difference(start).inMinutes / 60.0;
    return hour.clamp(0.0, timelineHours);
  }

  List<_SleepTimeLabel> _buildTimeLabels(DateTime timelineStart, double timelineHours) {
    final step = timelineHours <= 6
        ? 1
        : timelineHours <= 12
            ? 2
            : 3;
    final labels = <_SleepTimeLabel>[];

    for (var hour = 0; hour <= timelineHours.ceil(); hour += step) {
      labels.add(
        _SleepTimeLabel(
          hour: hour.toDouble().clamp(0.0, timelineHours),
          label: _formatSleepAxisLabel(timelineStart.add(Duration(hours: hour))),
        ),
      );
    }

    if (labels.isEmpty || labels.last.hour < timelineHours) {
      labels.add(
        _SleepTimeLabel(
          hour: timelineHours,
          label: _formatSleepAxisLabel(
            timelineStart.add(Duration(minutes: (timelineHours * 60).round())),
          ),
        ),
      );
    }

    return labels;
  }

  String _formatSleepAxisLabel(DateTime time) {
    final period = time.hour < 12 ? '오전' : '오후';
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  double _sleepChartXForHour(double hour, double chartWidth, double timelineHours) {
    final safeHours = timelineHours <= 0 ? 1.0 : timelineHours;
    return chartWidth * (hour / safeHours);
  }

  _SleepStage _toStage(BleSleepType sleep) {
    return switch (sleep) {
      BleSleepType.none || BleSleepType.unknown => _SleepStage.none,
      BleSleepType.awake => _SleepStage.awake,
      BleSleepType.rem => _SleepStage.rem,
      BleSleepType.light => _SleepStage.light,
      BleSleepType.deep => _SleepStage.deep,
    };
  }

  Widget _buildSleepSegment({
    required _SleepSegment segment,
    required double chartWidth,
    required double rowHeight,
    required double timelineHours,
  }) {
    final safeHours = timelineHours <= 0 ? 1.0 : timelineHours;
    final left = chartWidth * (segment.startHour / safeHours);
    final width = chartWidth * ((segment.endHour - segment.startHour) / safeHours);
    final rowIndex = switch (segment.stage) {
      _SleepStage.awake => 0,
      _SleepStage.rem => 1,
      _SleepStage.light => 2,
      _SleepStage.deep => 3,
      _SleepStage.none => 0,
    };
    final color = _segmentColor(segment.stage);
    final borderColor = _segmentBorderColor(segment.stage);
    final segmentHeight = _segmentHeight(segment.stage);
    final top = rowHeight * rowIndex + (rowHeight - segmentHeight) / 2;

    return Positioned(
      left: left,
      top: top,
      width: width.clamp(3.0, chartWidth).toDouble(),
      height: segmentHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(segment.stage == _SleepStage.awake ? 4 : 8),
          border: Border.all(color: borderColor, width: segment.stage == _SleepStage.awake ? 0 : 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.16),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  double _segmentHeight(_SleepStage stage) {
    return switch (stage) {
      _SleepStage.none => 0.0,
      _SleepStage.awake => 46.0,
      _SleepStage.rem => 18.0,
      _SleepStage.light => 28.0,
      _SleepStage.deep => 18.0,
    };
  }

  Color _segmentColor(_SleepStage stage) {
    return switch (stage) {
      _SleepStage.none => Colors.transparent,
      _SleepStage.awake => const Color(0xFFFF9A90),
      _SleepStage.rem => const Color(0xFF18BFEF),
      _SleepStage.light => const Color(0xFF1784F2),
      _SleepStage.deep => const Color(0xFF3B36C8),
    };
  }

  Color _segmentBorderColor(_SleepStage stage) {
    return switch (stage) {
      _SleepStage.none => Colors.transparent,
      _SleepStage.awake => Colors.transparent,
      _SleepStage.rem => const Color(0xFF7EE2FF),
      _SleepStage.light => const Color(0xFF8CCBFF),
      _SleepStage.deep => const Color(0xFF8B88F7),
    };
  }
}

class _SleepTimelineData {
  final List<_SleepSegment> segments;
  final List<_SleepTimeLabel> timeLabels;
  final double timelineHours;
  final Duration summary;
  final DateTime? date;

  const _SleepTimelineData({
    required this.segments,
    required this.timeLabels,
    required this.timelineHours,
    required this.summary,
    required this.date,
  });
}

class _SleepConnectorPainter extends CustomPainter {
  final List<_SleepSegment> segments;
  final double timelineHours;

  const _SleepConnectorPainter({
    required this.segments,
    required this.timelineHours,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < segments.length - 1; i++) {
      final current = segments[i];
      final next = segments[i + 1];
      final gap = next.startHour - current.endHour;

      if (gap > 0.22) continue;

      final startX = size.width * (current.endHour / timelineHours);
      final endX = size.width * (next.startHour / timelineHours);
      final currentRect = _segmentRect(current, size);
      final nextRect = _segmentRect(next, size);
      final start = Offset(startX, currentRect.center.dy);
      final end = Offset(endX, nextRect.center.dy);
      final controlX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          controlX,
          start.dy,
          controlX,
          end.dy,
          end.dx,
          end.dy,
        );

      final paint = Paint()
        ..color = _connectorColor(current.stage, next.stage)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paint);
    }
  }

  Rect _segmentRect(_SleepSegment segment, Size size) {
    final rowHeight = size.height / 4;
    final rowIndex = switch (segment.stage) {
      _SleepStage.awake => 0,
      _SleepStage.rem => 1,
      _SleepStage.light => 2,
      _SleepStage.deep => 3,
      _SleepStage.none => 0,
    };
    final height = switch (segment.stage) {
      _SleepStage.none => 0.0,
      _SleepStage.awake => 46.0,
      _SleepStage.rem => 18.0,
      _SleepStage.light => 28.0,
      _SleepStage.deep => 18.0,
    };
    final left = size.width * (segment.startHour / timelineHours);
    final right = size.width * (segment.endHour / timelineHours);
    final top = rowHeight * rowIndex + (rowHeight - height) / 2;
    return Rect.fromLTRB(left, top, right, top + height);
  }

  Color _connectorColor(_SleepStage current, _SleepStage next) {
    if (current == _SleepStage.awake || next == _SleepStage.awake) {
      return const Color(0x33FF8A80);
    }
    if (current == _SleepStage.deep || next == _SleepStage.deep) {
      return const Color(0x4D98A2FF);
    }
    if (current == _SleepStage.rem || next == _SleepStage.rem) {
      return const Color(0x4D26C6F9);
    }
    return const Color(0x4D1E88FF);
  }

  @override
  bool shouldRepaint(covariant _SleepConnectorPainter oldDelegate) {
    return oldDelegate.segments != segments || oldDelegate.timelineHours != timelineHours;
  }
}

class _SleepTimeLabel {
  final double hour;
  final String label;

  const _SleepTimeLabel({
    required this.hour,
    required this.label,
  });
}

class _SleepChartGridPainter extends CustomPainter {
  final List<_SleepTimeLabel> timeLabels;
  final double timelineHours;

  const _SleepChartGridPainter({
    required this.timeLabels,
    required this.timelineHours,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    final verticalPaint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1;
    const rows = 4;
    final rowHeight = size.height / rows;

    for (var i = 0; i <= rows; i++) {
      final y = rowHeight * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontalPaint);
    }

    for (final label in timeLabels) {
      final x = size.width * (label.hour / timelineHours);
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), verticalPaint);
    }

    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, size.height),
      horizontalPaint,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashHeight = 4.0;
    const dashSpace = 4.0;
    var currentY = start.dy;

    while (currentY < end.dy) {
      final nextY = (currentY + dashHeight).clamp(start.dy, end.dy).toDouble();
      canvas.drawLine(Offset(start.dx, currentY), Offset(end.dx, nextY), paint);
      currentY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _SleepChartGridPainter oldDelegate) {
    return oldDelegate.timelineHours != timelineHours ||
        oldDelegate.timeLabels != timeLabels;
  }
}

class _TrendChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<DateTime> timestamps;
  final _AnalysisRange range;
  final Color color;
  final String title;
  final double? minY;
  final double? maxY;

  const _TrendChart({
    required this.spots,
    required this.timestamps,
    required this.range,
    required this.color,
    required this.title,
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionTitle(title: title),
        AppCard(
          child: SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
                    color: color,
                    barWidth: 3,
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: _bottomInterval,
                      getTitlesWidget: _buildBottomTitle,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, drawVerticalLine: false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double get _bottomInterval {
    if (spots.length <= 1) return 1;
    return ((spots.length - 1) / 3).clamp(1, spots.length.toDouble()).toDouble();
  }

  Widget _buildBottomTitle(double value, TitleMeta meta) {
    final index = value.round();
    if (index < 0 || index >= timestamps.length) {
      return const SizedBox.shrink();
    }

    final shouldShow = index == 0 || index == timestamps.length - 1 || index % _bottomInterval.round() == 0;
    if (!shouldShow) return const SizedBox.shrink();

    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 6,
      child: Text(
        _formatTimestamp(timestamps[index]),
        style: const TextStyle(fontSize: 9, color: Colors.grey),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final meridiem = timestamp.hour < 12 ? '오전' : '오후';

    return switch (range) {
      _AnalysisRange.minute => '$meridiem $hour:$minute',
      _AnalysisRange.hour => '$meridiem $hour시',
    };
  }
}
