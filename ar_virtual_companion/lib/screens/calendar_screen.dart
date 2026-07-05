import 'package:ar_ai_girl_friend/providers/personality_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/supabase_service.dart';
import 'journal_entry_screen.dart';
import 'memory_screen.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  Map<String, Map<String, dynamic>> _logs = {};
  bool _isLoading = true;

  Map<String, List<Map<String, dynamic>>> _memories = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchMonthData(_focusedDay);
  }

  /// Supabase 存 UTC；必須 toLocal() 後再取年月日，否則例如香港凌晨會變前一天。
  static DateTime? _parseProfileTimestampLocal(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toLocal();
  }

  static bool _isBirthdayDay(DateTime day, DateTime? birthdayLocal) {
    if (birthdayLocal == null) return false;
    return day.month == birthdayLocal.month && day.day == birthdayLocal.day;
  }

  Widget _buildBirthdayBanner() {
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary.withOpacity(0.12),
                  Colors.pink.shade50.withOpacity(0.9),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.pink.shade100.withOpacity(0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.cake_rounded, size: 40, color: Colors.pink.shade400),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Happy Birthday!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Wishing you a day full of smiles and warmth ✨',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: _navigateToJournalEntry,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Entry'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchMonthData(DateTime date) async {
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    
    final start = DateTime(date.year, date.month, 1);
    final lastDayOfMonth = DateTime(date.year, date.month + 1, 0);
    final nextMonthStart = DateTime(date.year, date.month + 1, 1);

    final logs = await SupabaseService.fetchDailyLogs(start, lastDayOfMonth);
    // `created_at` 為 timestamptz：用 [當月1日 00:00, 下月1日 00:00) 才包含當月最後一天全天
    final memories = await SupabaseService.fetchMemories(
      start,
      nextMonthStart,
      exclusiveEnd: true,
    );
    
    final newLogs = <String, Map<String, dynamic>>{};
    for (var log in logs) {
      // `date` 欄位為純日期；解析後轉本地再格式化，與記憶分組一致
      final logDate = DateTime.parse(log['date'].toString()).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(logDate);
      newLogs[dateKey] = log;
    }

    final newMemories = <String, List<Map<String, dynamic>>>{};
    for (var mem in memories) {
      final memDate = DateTime.parse(mem['created_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(memDate);
      if (newMemories[dateKey] == null) {
        newMemories[dateKey] = [];
      }
      newMemories[dateKey]!.add(mem);
    }

    if (mounted) {
      setState(() {
        _logs = newLogs;
        _memories = newMemories;
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateToJournalEntry() async {
    if (_selectedDay == null) return;
    
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final existingLog = _logs[dateKey];
    
    // Navigate to new screen and wait for result (true if data changed)
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JournalEntryScreen(
          date: _selectedDay!,
          existingLog: existingLog,
        ),
      ),
    );

    if (result == true) {
      _fetchMonthData(_focusedDay); // Refresh data
    }
  }

  Color _getMoodColor(String? emotion) {
    switch (emotion) {
      case 'Happy': return Colors.orange;
      case 'Neutral': return Colors.amber;
      case 'Anxious': return Colors.blue;
      case 'Sad': return Colors.indigo;
      case 'Angry': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getMoodEmoji(String? emotion) {
    switch (emotion) {
      case 'Happy': return '😄';
      case 'Neutral': return '😐';
      case 'Anxious': return '😟';
      case 'Sad': return '😢';
      case 'Angry': return '😡';
      default: return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 MediaQuery 獲取螢幕尺寸
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    final profile = ref.watch(userProfileProvider).valueOrNull;
    final DateTime? meetingDateLocal = _parseProfileTimestampLocal(profile?['created_at']);
    final DateTime? birthdayLocal = _parseProfileTimestampLocal(profile?['birthday']);

    return Scaffold(
      appBar: AppBar(title: const Text('My Journal')),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16), // 小螢幕縮小邊距
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              rowHeight: isSmallScreen ? 42 : 52, // 小螢幕縮小日曆列高
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
                CalendarFormat.twoWeeks: '2 Weeks',
                CalendarFormat.week: 'Week',
              },
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedDay, selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _fetchMonthData(selectedDay);
                }
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
                _fetchMonthData(focusedDay);
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  final dateKey = DateFormat('yyyy-MM-dd').format(date);

                  final isMeetingDay = meetingDateLocal != null &&
                      date.year == meetingDateLocal.year &&
                      date.month == meetingDateLocal.month &&
                      date.day == meetingDateLocal.day;

                  final isBirthday = birthdayLocal != null &&
                      date.month == birthdayLocal.month &&
                      date.day == birthdayLocal.day;

                  // 1. 相遇日 + 生日（可同一天）
                  if (isMeetingDay || isBirthday) {
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (isMeetingDay)
                          Positioned(
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '相遇日',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isMeetingDay)
                                Icon(
                                  Icons.favorite,
                                  color: Theme.of(context).primaryColor,
                                  size: 14,
                                ),
                              if (isMeetingDay && isBirthday) const SizedBox(width: 4),
                              if (isBirthday)
                                Icon(
                                  Icons.cake,
                                  color: Colors.pink.shade400,
                                  size: 14,
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  // 2. Mood Logs
                  if (_logs.containsKey(dateKey)) {
                    final emotion = _logs[dateKey]!['emotion'] as String?;
                    return Positioned(
                      bottom: 1,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getMoodColor(emotion),
                        ),
                      ),
                    );
                  }
                  return null;
                },
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
                outsideDaysVisible: false, // Cleaner look
              ),
            ),
          ),
          if (_isBirthdayDay(_selectedDay ?? _focusedDay, birthdayLocal))
            _buildBirthdayBanner(),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _buildLogList(birthdayLocal),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(DateTime? birthdayLocal) {
    if (_selectedDay == null) return const SizedBox.shrink();
    
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final log = _logs[dateKey];
    final dayMemories = _memories[dateKey]; // Get memories for the day
    final showBirthdayAddButton =
        _isBirthdayDay(_selectedDay!, birthdayLocal);
    
    // Empty State
    if (log == null && (dayMemories == null || dayMemories.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_calendar, size: 48, color: Theme.of(context).primaryColor.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(
              'No entries for ${DateFormat('MMM d').format(_selectedDay!)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
            if (!showBirthdayAddButton) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToJournalEntry,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add Entry'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        // Journal Section
        if (log != null) ...[
          _buildSectionHeader('Journal Entry', Icons.book),
          const SizedBox(height: 12),
          _buildJournalCard(log),
          const SizedBox(height: 24),
        ] else ...[
          Center(
             child: TextButton.icon(
               onPressed: _navigateToJournalEntry,
               icon: const Icon(Icons.add_circle_outline),
               label: const Text('Create Journal Entry'),
               style: TextButton.styleFrom(
                 foregroundColor: Theme.of(context).primaryColor,
               ),
             ),
          ),
          const SizedBox(height: 24),
        ],

        // Memories Section
        if (dayMemories != null && dayMemories.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('Memories', Icons.memory),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MemoryScreen(),
                    ),
                  );
                },
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...dayMemories.map((memory) => _buildTimelineMemoryCard(memory)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildJournalCard(Map<String, dynamic> log) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (log['image_url'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: CachedNetworkImage(
                imageUrl: log['image_url'],
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 180,
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 180,
                  color: Colors.grey[200],
                  child: const Icon(Icons.error),
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getMoodColor(log['emotion']).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _getMoodEmoji(log['emotion']),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('MMM d, yyyy').format(_selectedDay!),
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Emotion: ${log['emotion'] ?? 'Unknown'}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: _navigateToJournalEntry,
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                Text(
                  log['content'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineMemoryCard(Map<String, dynamic> memory) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).secondaryHeaderColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chat_bubble_outline, size: 14, color: Theme.of(context).secondaryHeaderColor),
                ),
                const SizedBox(width: 10),
                Text(
                  DateFormat('h:mm a').format(DateTime.parse(memory['created_at']).toLocal()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (memory['category'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      memory['category'],
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              memory['content'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
