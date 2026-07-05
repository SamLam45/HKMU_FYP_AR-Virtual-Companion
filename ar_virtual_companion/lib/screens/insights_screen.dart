import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _memories = [];
  String _timeframe = 'Month'; // 'Week', 'Month'

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final now = DateTime.now();
    DateTime start;

    if (_timeframe == 'Week') {
      // 獲取過去 7 天 (包含今天)
      start = now.subtract(const Duration(days: 6));
      start = DateTime(start.year, start.month, start.day); // 歸零時間到午夜
    } else {
      // Default: Month → 過去 30 天 (包含今天)
      start = now.subtract(const Duration(days: 29));
      start = DateTime(start.year, start.month, start.day);
    }

    // Ensure we fetch data up to end of today
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final results = await Future.wait([
      SupabaseService.fetchDailyLogs(start, end),
      SupabaseService.fetchMemories(start, end),
    ]);
    final logs = results[0] as List<Map<String, dynamic>>;
    final memories = results[1] as List<Map<String, dynamic>>;

    // 將 logs 依照日期從舊到新排序，確保圖表從左到右顯示
    logs.sort(
      (a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])),
    );
    memories.sort(
      (a, b) => DateTime.parse(
        a['created_at'],
      ).compareTo(DateTime.parse(b['created_at'])),
    );

    if (mounted) {
      setState(() {
        _logs = logs;
        _memories = memories;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Companion Recap'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeframe Selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: ['Week', 'Month'].map((e) {
                          final isSelected = _timeframe == e;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _timeframe = e);
                                _fetchData();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context).primaryColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  e,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Companion Summary Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            context,
                            'Companion Moments',
                            '${_memories.length}',
                            Icons.chat_bubble_outline,
                            Colors.deepPurpleAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryCard(
                            context,
                            'Chat Streak',
                            _calculateCompanionStreak(),
                            Icons.local_fire_department_outlined,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            context,
                            'Peak Hour',
                            _calculatePeakHour(),
                            Icons.schedule,
                            Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryCard(
                            context,
                            'Journal Emotion quantity',
                            '${_logs.length}',
                            Icons.mood_outlined,
                            Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Emotion Trend Chart (supporting signal)
                    Text(
                      'Emotion Trend',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 300,
                      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).shadowColor.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _logs.isEmpty
                          ? Center(
                              child: Text(
                                'No emotion check-ins in this period.\nAdd a journal entry to see your trend.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 1,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey.withOpacity(0.1),
                                    strokeWidth: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      interval: 1,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        if (value == 1)
                                          return const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Text(
                                              '😡',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          );
                                        if (value == 2)
                                          return const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Text(
                                              '😢',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          );
                                        if (value == 3)
                                          return const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Text(
                                              '😟',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          );
                                        if (value == 4)
                                          return const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Text(
                                              '😐',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          );
                                        if (value == 5)
                                          return const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Text(
                                              '😄',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          );
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: _logs.length > 7
                                          ? (_logs.length / 5).ceilToDouble()
                                          : 1,
                                      getTitlesWidget: (value, meta) {
                                        if (value < 0 || value >= _logs.length) {
                                          return const SizedBox.shrink();
                                        }

                                        // 避免標籤重疊：只在指定的 interval 處繪製標籤
                                        final double interval = _logs.length > 7
                                            ? (_logs.length / 5).ceilToDouble()
                                            : 1;
                                            
                                        final int intValue = value.round();
                                        final int intInterval = interval.round();
                                        
                                        if (intValue % intInterval != 0) {
                                          return const SizedBox.shrink();
                                        }

                                        final index = intValue;
                                        if (index >= _logs.length) {
                                          return const SizedBox.shrink();
                                        }

                                        final date = DateTime.parse(
                                          _logs[index]['date'],
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            DateFormat('MM/dd').format(date),
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                minX: 0,
                                maxX: (_logs.length - 1).toDouble(),
                                minY: 0,
                                maxY: 6,
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _logs.asMap().entries.map((e) {
                                      final emotion =
                                          e.value['emotion'] as String?;
                                      return FlSpot(
                                        e.key.toDouble(),
                                        _getEmotionScore(emotion).toDouble(),
                                      );
                                    }).toList(),
                                    isCurved: true,
                                    curveSmoothness: 0.35,
                                    color: Theme.of(context).primaryColor,
                                    barWidth: 4,
                                    isStrokeCapRound: true,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter:
                                          (spot, percent, barData, index) =>
                                              FlDotCirclePainter(
                                                radius: 6,
                                                color: Colors.white,
                                                strokeWidth: 3,
                                                strokeColor: Theme.of(
                                                  context,
                                                ).primaryColor,
                                              ),
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(
                                            context,
                                          ).primaryColor.withOpacity(0.4),
                                          Theme.of(
                                            context,
                                          ).primaryColor.withOpacity(0.0),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (touchedSpot) =>
                                        Colors.white,
                                    tooltipPadding: const EdgeInsets.all(8),
                                    tooltipBorder: BorderSide(
                                      color: Colors.grey.withOpacity(0.2),
                                    ),
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots.map((spot) {
                                        final log = _logs[spot.x.toInt()];
                                        final date = DateTime.parse(
                                          log['date'],
                                        );
                                        final emotion =
                                            log['emotion'] ?? 'Unknown';
                                        return LineTooltipItem(
                                          '${DateFormat('MMM d').format(date)}\n',
                                          TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'Emotion: $emotion',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList();
                                    },
                                  ),
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 32),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateCompanionStreak() {
    if (_memories.isEmpty) return '0d';
    final days = <String>{};
    for (final m in _memories) {
      final createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (createdAt == null) continue;
      final local = createdAt.toLocal();
      days.add(DateFormat('yyyy-MM-dd').format(local));
    }
    if (days.isEmpty) return '0d';

    final sorted = days.toList()..sort();
    DateTime? prev;
    int current = 0;
    int best = 0;

    for (final d in sorted) {
      final dt = DateTime.tryParse(d);
      if (dt == null) continue;
      if (prev == null) {
        current = 1;
      } else {
        final diff = dt.difference(prev).inDays;
        current = (diff == 1) ? (current + 1) : 1;
      }
      if (current > best) best = current;
      prev = dt;
    }
    return '${best}d';
  }

  String _calculatePeakHour() {
    if (_memories.isEmpty) return '-';
    final counts = List<int>.filled(24, 0);
    for (final m in _memories) {
      final createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (createdAt == null) continue;
      final h = createdAt.toLocal().hour;
      counts[h] += 1;
    }
    var bestHour = 0;
    var bestCount = -1;
    for (var h = 0; h < 24; h++) {
      final c = counts[h];
      if (c > bestCount) {
        bestCount = c;
        bestHour = h;
      }
    }
    final start = DateTime(2000, 1, 1, bestHour);
    return DateFormat('ha').format(start);
  }

  int _getEmotionScore(String? emotion) {
    switch (emotion) {
      case 'Happy':
        return 5;
      case 'Neutral':
        return 4;
      case 'Anxious':
        return 3;
      case 'Sad':
        return 2;
      case 'Angry':
        return 1;
      default:
        return 4;
    }
  }
}
