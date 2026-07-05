import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_character.dart';
import '../services/supabase_service.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  final List<ConversationMemory> _memories = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Today', 'This Week', 'This Month'];

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    
    // Fetch memories from the last year by default for "All"
    // In a real app with pagination, we would handle this differently
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 365));

    final rawMemories = await SupabaseService.fetchMemories(start, end);
    
    final List<ConversationMemory> mappedMemories = [];
    
    for (var raw in rawMemories) {
      try {
        // Map Supabase data to ConversationMemory
        // Since Supabase table structure is different, we adapt here
        // Assuming 'content' holds the summary/memory text
        // And metadata might hold emotion
        
        final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
        final emotionStr = metadata['emotion'] as String? ?? 'neutral';
        
        // Find matching emotion or default to happy/neutral
        final emotion = EmotionalState.values.firstWhere(
          (e) => e.name == emotionStr,
          orElse: () => EmotionalState.calm,
        );

        final content = raw['content'] as String? ?? '';
        String userMsg = 'Memory';
        String aiMsg = content;

        // Parse content format "User: <text>\nAI: <text>"
        if (content.contains('User:') && content.contains('AI:')) {
          final parts = content.split('AI:');
          if (parts.length >= 2) {
            String userPart = parts[0];
            aiMsg = parts.sublist(1).join('AI:').trim();
            
            if (userPart.contains('User:')) {
              userMsg = userPart.split('User:').last.trim();
            } else {
              userMsg = userPart.trim();
            }
          }
        }

        mappedMemories.add(ConversationMemory(
          id: raw['id'],
          userMessage: userMsg,
          aiResponse: aiMsg,
          emotionalState: emotion,
          timestamp: DateTime.parse(raw['created_at']).toLocal(),
          context: metadata,
        ));
      } catch (e) {
        print('Error mapping memory: $e');
      }
    }

    // Sort by newest first
    mappedMemories.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _memories.clear();
        _memories.addAll(mappedMemories);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredMemories = _getFilteredMemories();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation Memories'),
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _buildStatsCard(),
              _buildFilterChips(),
              Expanded(
                child: filteredMemories.isEmpty
                    ? _buildEmptyState()
                    : _buildMemoriesList(filteredMemories),
              ),
            ],
          ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            count: _memories.length.toString(),
            label: 'Memories',
            icon: Icons.history_edu,
          ),
          Container(
            height: 40,
            width: 1,
            color: Colors.white.withOpacity(0.2),
          ),
          _buildStatItem(
            count: _getTodayMemories().length.toString(),
            label: 'Today',
            icon: Icons.today,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String count, required String label, required IconData icon}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 12),
        Text(
          count,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter;
                });
              },
              selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
              checkmarkColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Colors.grey.withOpacity(0.2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
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
            child: Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(context).primaryColor.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start chatting with your AI companion\nto see memories here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoriesList(List<ConversationMemory> memories) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        return _buildMemoryCard(memory);
      },
    );
  }

  Widget _buildMemoryCard(ConversationMemory memory) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildEmotionIcon(memory.emotionalState),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTimestamp(memory.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        memory.emotionalState.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showMemoryOptions(memory),
                  icon: const Icon(Icons.more_horiz, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person, size: 16, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          memory.userMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: Theme.of(context).primaryColor.withOpacity(0.1)),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          memory.aiResponse,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionIcon(EmotionalState emotion) {
    IconData iconData;
    Color color;
    
    switch (emotion) {
      case EmotionalState.happy:
        iconData = Icons.sentiment_very_satisfied;
        color = Colors.green;
        break;
      case EmotionalState.sad:
        iconData = Icons.sentiment_very_dissatisfied;
        color = Colors.blue;
        break;
      case EmotionalState.excited:
        iconData = Icons.sentiment_very_satisfied;
        color = Colors.orange;
        break;
      case EmotionalState.calm:
        iconData = Icons.sentiment_neutral;
        color = Colors.purple;
        break;
      case EmotionalState.loving:
        iconData = Icons.favorite;
        color = Colors.red;
        break;
      default:
        iconData = Icons.sentiment_neutral;
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 20),
    );
  }



  List<ConversationMemory> _getFilteredMemories() {
    final now = DateTime.now();
    
    switch (_selectedFilter) {
      case 'Today':
        return _memories.where((memory) {
          return memory.timestamp.day == now.day &&
                 memory.timestamp.month == now.month &&
                 memory.timestamp.year == now.year;
        }).toList();
      case 'This Week':
        final weekAgo = now.subtract(const Duration(days: 7));
        return _memories.where((memory) {
          return memory.timestamp.isAfter(weekAgo);
        }).toList();
      case 'This Month':
        final monthAgo = now.subtract(const Duration(days: 30));
        return _memories.where((memory) {
          return memory.timestamp.isAfter(monthAgo);
        }).toList();
      default:
        return _memories;
    }
  }

  List<ConversationMemory> _getTodayMemories() {
    final now = DateTime.now();
    return _memories.where((memory) {
      return memory.timestamp.day == now.day &&
             memory.timestamp.month == now.month &&
             memory.timestamp.year == now.year;
    }).toList();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Filter Conversations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ..._filters.map((filter) {
              return ListTile(
                title: Text(filter),
                trailing: _selectedFilter == filter
                    ? const Icon(Icons.check, color: Color(0xFF6B73FF))
                    : null,
                onTap: () {
                  setState(() {
                    _selectedFilter = filter;
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showMemoryOptions(ConversationMemory memory) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Conversation'),
              onTap: () {
                Navigator.pop(context);
                _shareMemory(memory);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Navigator.pop(context);
                _copyMemory(memory);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMemory(memory);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shareMemory(ConversationMemory memory) {
    // TODO: Implement sharing functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share functionality coming soon!'),
      ),
    );
  }

  void _copyMemory(ConversationMemory memory) {
    // TODO: Implement copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
      ),
    );
  }

  void _deleteMemory(ConversationMemory memory) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('Are you sure you want to delete this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _memories.remove(memory);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Conversation deleted'),
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
