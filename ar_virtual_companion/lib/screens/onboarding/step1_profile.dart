import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/onboarding_provider.dart';
import 'package:intl/intl.dart';

class Step1Profile extends ConsumerStatefulWidget {
  const Step1Profile({super.key});

  @override
  ConsumerState<Step1Profile> createState() => _Step1ProfileState();
}

class _Step1ProfileState extends ConsumerState<Step1Profile> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _aiNameController;
  late TextEditingController _birthdayController;

  void _syncFieldsFromProvider() {
    final s = ref.read(onboardingProvider);
    if (_usernameController.text != s.username) {
      _usernameController.text = s.username;
    }
    if (_aiNameController.text != s.aiNickname) {
      _aiNameController.text = s.aiNickname;
    }
    final b = s.birthday != null ? DateFormat('yyyy-MM-dd').format(s.birthday!) : '';
    if (_birthdayController.text != b) {
      _birthdayController.text = b;
    }
  }

  @override
  void initState() {
    super.initState();
    final state = ref.read(onboardingProvider);
    _usernameController = TextEditingController(text: state.username);
    _aiNameController = TextEditingController(text: state.aiNickname);
    _birthdayController = TextEditingController(
      text: state.birthday != null ? DateFormat('yyyy-MM-dd').format(state.birthday!) : '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _aiNameController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      ref.read(onboardingProvider.notifier).setBirthday(picked);
      setState(() {
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      onboardingProvider.select((s) => s.currentStep),
      (prev, next) {
        if (next == 0 && prev != null && prev != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncFieldsFromProvider();
          });
        }
      },
    );

    final notifier = ref.read(onboardingProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Let\'s get started',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell us a bit about yourself to create your perfect companion.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            
            // Username Field
            TextFormField(
              controller: _usernameController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'Your Name',
                prefixIcon: Icon(Icons.person),
              ),
              onChanged: (value) => notifier.setUsername(value),
            ),
            
            const SizedBox(height: 20),

            // Birthday Field
            GestureDetector(
              onTap: () => _selectDate(context),
              child: AbsorbPointer(
                child: TextFormField(
                  controller: _birthdayController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Your Birthday',
                    prefixIcon: Icon(Icons.cake),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // AI Nickname Field
            TextFormField(
              controller: _aiNameController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'Companion\'s Name',
                prefixIcon: Icon(Icons.face_retouching_natural),
              ),
              onChanged: (value) => notifier.setAiNickname(value),
            ),
          ],
        ),
      ),
    );
  }
}
