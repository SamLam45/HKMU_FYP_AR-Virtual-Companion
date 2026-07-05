import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ARSettingsModal extends StatefulWidget {
  final VoidCallback onSettingsChanged;

  const ARSettingsModal({super.key, required this.onSettingsChanged});

  @override
  State<ARSettingsModal> createState() => _ARSettingsModalState();
}

class _ARSettingsModalState extends State<ARSettingsModal> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _personas = [];
  Map<String, dynamic>? _userProfile;
  late PageController _pageController;
  int _currentPage = 0;
  
  // Voice settings
  String _selectedVoice = 'Kore';
  final Map<String, List<String>> _genderVoices = {
    'female': ['Kore', 'Aoede'],
    'male': ['Puck', 'Charon', 'Fenrir'],
  };

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _fetchData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Fetch Profile
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      
      // Fetch Personas
      final personasResponse = await Supabase.instance.client
          .from('personas')
          .select()
          .order('id');

      if (mounted) {
        setState(() {
          _userProfile = profileResponse;
          _personas = List<Map<String, dynamic>>.from(personasResponse);
          
          // Set initial voice from preferences
          final prefs = _userProfile!['preferences'] as Map<String, dynamic>? ?? {};
          _selectedVoice = prefs['gemini_voice'] as String? ?? 'Kore';
          
          // Set initial page based on selected_persona_id
          final selectedId = _userProfile!['selected_persona_id'];
          if (selectedId != null) {
            final index = _personas.indexWhere((p) => p['id'] == selectedId);
            if (index != -1) {
              _currentPage = index;
              // Wait for build to complete before jumping
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) {
                  _pageController.jumpToPage(index);
                }
              });
            }
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching settings data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePersonality(int index) async {
    if (_userProfile == null) return;
    
    final persona = _personas[index];
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'selected_persona_id': persona['id']})
          .eq('id', _userProfile!['id']);
          
      setState(() {
        _currentPage = index;
      });
      
      widget.onSettingsChanged();
    } catch (e) {
      debugPrint("Error updating personality: $e");
    }
  }

  Future<void> _updateVoice(String voice) async {
    if (_userProfile == null) return;
    
    try {
      final prefs = Map<String, dynamic>.from(_userProfile!['preferences'] as Map? ?? {});
      prefs['gemini_voice'] = voice;
      
      await Supabase.instance.client
          .from('profiles')
          .update({'preferences': prefs})
          .eq('id', _userProfile!['id']);

      setState(() {
        _selectedVoice = voice;
        // Update local profile copy
        _userProfile!['preferences'] = prefs;
      });
      
      widget.onSettingsChanged();
    } catch (e) {
      debugPrint("Error updating voice: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final gender = _userProfile?['gender'] as String? ?? 'female';
    // Normalize gender string
    final normalizedGender = gender.toLowerCase();
    final availableVoices = _genderVoices[normalizedGender] ?? ['Kore'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Personality Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                const Text(
                  '個性選擇 (Personality)',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 240,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _personas.length,
              onPageChanged: (index) {
                // Auto-center happens by PageView design
                // We update selection immediately or wait? 
                // Let's update on page snap.
                _updatePersonality(index);
              },
              itemBuilder: (context, index) {
                final persona = _personas[index];
                final isSelected = index == _currentPage;
                
                return AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double value = 1.0;
                    if (_pageController.position.haveDimensions) {
                      value = _pageController.page! - index;
                      value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                    } else {
                      value = isSelected ? 1.0 : 0.7;
                    }
                    
                    return Center(
                      child: SizedBox(
                        height: Curves.easeOut.transform(value) * 240,
                        width: Curves.easeOut.transform(value) * 350,
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      _updatePersonality(index);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2A2A2A) : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected ? Border.all(color: Colors.cyanAccent, width: 2) : Border.all(color: Colors.white10),
                        boxShadow: isSelected ? [
                          BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)
                        ] : [],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.white10,
                            backgroundImage: persona['avatar_url'] != null 
                                ? CachedNetworkImageProvider(persona['avatar_url']) 
                                : null,
                            child: persona['avatar_url'] == null 
                                ? Text(persona['name'][0], style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold))
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            persona['name'],
                            style: TextStyle(
                              color: isSelected ? Colors.cyanAccent : Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            persona['description'] ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "Selected",
                                style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Divider(color: Colors.white24, height: 40),
          ),

          // 2. Voice Settings Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.record_voice_over, color: Colors.purpleAccent),
                    const SizedBox(width: 8),
                    const Text(
                      '語音設定 (Voice)',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '根據您的性別 ($gender) 推薦:',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: availableVoices.map((voice) {
                    final isSelected = _selectedVoice == voice;
                    return ChoiceChip(
                      label: Text(voice),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) _updateVoice(voice);
                      },
                      selectedColor: Colors.purpleAccent.withOpacity(0.3),
                      backgroundColor: const Color(0xFF2A2A2A),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.purpleAccent : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? Colors.purpleAccent : Colors.white10,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
