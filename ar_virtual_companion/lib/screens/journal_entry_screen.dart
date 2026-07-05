import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../services/supabase_service.dart';
import '../services/ai_partner_service.dart';

class JournalEntryScreen extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic>? existingLog;

  const JournalEntryScreen({
    super.key,
    required this.date,
    this.existingLog,
  });

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final TextEditingController _contentController = TextEditingController();
  String _selectedEmotion = 'Happy';
  String? _currentImageUrl;
  File? _newImageFile;
  bool _isSaving = false;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _emotions = [
    {'label': 'Happy', 'emoji': '😄', 'color': Colors.orange},
    {'label': 'Neutral', 'emoji': '😐', 'color': Colors.amber},
    {'label': 'Anxious', 'emoji': '😟', 'color': Colors.blue},
    {'label': 'Sad', 'emoji': '😢', 'color': Colors.indigo},
    {'label': 'Angry', 'emoji': '😡', 'color': Colors.red},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingLog != null) {
      _contentController.text = widget.existingLog!['content'] ?? '';
      _selectedEmotion = widget.existingLog!['emotion'] ?? 'Happy';
      _currentImageUrl = widget.existingLog!['image_url'];
    }
    // 進入畫面即喚醒後端，減少儲存後 force refresh 的等待感
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ARPartnerService()
            .prepareBackend(forceRefresh: false)
            .catchError((_) {}),
      );
    });
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                  
                  if (pickedFile != null) {
                    setState(() {
                      _newImageFile = File(pickedFile.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.camera);
                  
                  if (pickedFile != null) {
                    setState(() {
                      _newImageFile = File(pickedFile.path);
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveLog() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something about your day')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Upload image if new one selected
    String? imageUrl = _currentImageUrl;
    if (_newImageFile != null) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      imageUrl = await SupabaseService.uploadJournalImage(_newImageFile!.path, fileName);
    }

    try {
      final aiSummary = "It sounds like you're feeling $_selectedEmotion today. I'm here for you!";

      await SupabaseService.saveDailyLog(
        date: widget.date,
        content: _contentController.text.trim(),
        emotion: _selectedEmotion,
        aiSummary: aiSummary,
        imageUrl: imageUrl,
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteLog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('Are you sure you want to delete this journal entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await SupabaseService.deleteDailyLog(widget.date);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          DateFormat('MMMM d, yyyy').format(widget.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.existingLog != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isLoading ? null : _deleteLog,
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Emotion Selection
                const Text(
                  'How was your day?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: _emotions.map((emotion) {
                    final label = emotion['label'] as String;
                    final isSelected = _selectedEmotion == label;
                    final color = emotion['color'] as Color;
                    final emoji = emotion['emoji'] as String;
                    
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedEmotion = label),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic, // Changed from elasticOut to prevent negative blurRadius during lerp
                              padding: EdgeInsets.all(isSelected ? 12.0 : 8.0),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withOpacity(0.15) : Colors.grey[50],
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
                                    blurRadius: isSelected ? 8.0 : 0.0,
                                    spreadRadius: isSelected ? 1.0 : 0.0,
                                    offset: isSelected ? const Offset(0, 3) : Offset.zero,
                                  )
                                ],
                                border: Border.all(
                                  color: isSelected ? color : Colors.transparent,
                                  width: 2.0,
                                ),
                              ),
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.elasticOut, // Scale can safely use elasticOut
                                scale: isSelected ? 1.2 : 1.0,
                                child: Text(
                                  emoji,
                                  style: const TextStyle(
                                    fontSize: 30, // Base size, scaled by AnimatedScale
                                    shadows: [],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11, // Slightly smaller to fit better
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? color : Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                
                const SizedBox(height: 32),
                
                // Content Input
                TextField(
                  controller: _contentController,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Write about your day...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(20),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Image Picker
                InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                      image: _newImageFile != null
                        ? DecorationImage(image: FileImage(_newImageFile!), fit: BoxFit.cover)
                        : _currentImageUrl != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(_currentImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (_newImageFile == null && _currentImageUrl == null)
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'Add a photo',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : null,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Save Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveLog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSaving
                      ? const SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                        )
                      : const Text(
                          'Save Journal',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}