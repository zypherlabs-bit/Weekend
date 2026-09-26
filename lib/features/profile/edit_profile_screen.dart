import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/supabase_config.dart';
import '../../providers/weekend_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/image_optimizer.dart';
import '../../repositories/profile_repository.dart';

/// Personal Details (onboarding + edit profile).
///
/// This is the immediate next page after signup: the session stays active and
/// the profile is saved for the authenticated Supabase user. Existing users
/// with a complete profile continue into the app after saving.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _occupationController = TextEditingController();
  final _educationController = TextEditingController();
  final _favoriteMusicController = TextEditingController();
  final _idealWeekendController = TextEditingController();
  String _selectedGender = 'Man';
  String _selectedRelationshipIntent = 'Dating & Weekend Plans';
  List<String> _selectedInterests = [];
  Map<String, bool> _weekendAvailability = {};
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  final List<String> _availableGenders = [
    'Man',
    'Woman',
    'Non-binary',
    'Prefer not to say',
  ];
  final List<String> _availableRelationshipIntents = [
    'Dating',
    'Long-term relationship',
    'New people & Friendships',
    'Dating & Weekend Plans',
  ];
  final List<String> _availableInterests = [
    'Specialty Coffee',
    'Hiking',
    'Indie Music',
    'Cycling',
    'Travel',
    'F1',
    'Photography',
    'Plant Parenting',
    'Matcha',
    'Coffee Roasting',
    'Jazz',
    'Baking',
    'Books',
    'Vintage Shopping',
    'Fusion Cooking',
    'Gallery Hopping',
    'Acoustic Gigs',
    'Hill Climbs',
    'Brunch Spots',
    'Waterfall Treks',
  ];
  final List<String> _weekendDays = ['Saturday', 'Sunday'];
  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    // Pull the saved row first: sign-up wizard answers (name, gender, goal)
    // live in `profiles` and must prefill this form instead of the neutral
    // placeholder from WeekendState.initial().
    await ref.read(weekendProvider.notifier).loadCurrentUser();
    if (!mounted) return;
    final user = ref.read(weekendProvider).currentUser;
    _nameController.text = user.name;
    _bioController.text = user.bio;
    _cityController.text = user.city;
    _occupationController.text = user.occupation;
    _educationController.text = user.education;
    _favoriteMusicController.text = user.favoriteMusic;
    _idealWeekendController.text = user.idealWeekend;
    // Normalise the two dropdown-backed values against their option lists.
    // The neutral placeholder profile (or a legacy row) can carry a label the
    // dropdown does not offer, which would leave an unselectable — and
    // unvalidatable — field and make Save appear to do nothing.
    _selectedGender = _availableGenders.contains(user.gender)
        ? user.gender
        : _availableGenders.first;
    _selectedRelationshipIntent =
        _availableRelationshipIntents.contains(user.relationshipIntent)
            ? user.relationshipIntent
            : _availableRelationshipIntents.first;
    _selectedInterests = List.from(user.interests);
    _weekendAvailability = Map.from(user.weekendAvailability);
    if (_weekendAvailability.isEmpty) {
      _weekendAvailability = {'Saturday': false, 'Sunday': false};
    }
    // Rebuild so the freshly loaded values show (initState already built
    // once while the load was in flight).
    if (mounted) setState(() {});
  }

  /// The account every write is filed under.
  ///
  /// Taken from the Supabase auth session, never from `currentUser.id`, which
  /// is the `'me'` placeholder until the profile load resolves.
  String? get _authUserId {
    final id = SupabaseConfig.client?.auth.currentUser?.id;
    if (id == null || id.isEmpty || id == 'unauthenticated' || id == 'me') {
      return null;
    }
    return id;
  }

  /// Human-readable reason a save failed, without leaking tokens or internals.
  /// Repositories already map the common PostgREST/Storage failures to
  /// actionable StateErrors; this only strips SDK prefixes and maps any
  /// leftover network failure.
  String _readableSaveError(Object e) {
    final text = e
        .toString()
        .replaceFirst(RegExp(r'^(StateError|Exception)\s*:\s*'), '')
        .replaceFirst('Bad state: ', '');
    if (e is StateError || e is ArgumentError) return text;
    final lower = text.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timeout')) {
      return 'Network error. Check your connection and try again.';
    }
    return text;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    if (_authUserId == null) {
      _showError('You are not signed in, so nothing was saved.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = ref.read(weekendProvider).currentUser;
      final updatedProfile = user.copyWith(
        name: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        city: _cityController.text.trim(),
        occupation: _occupationController.text.trim(),
        education: _educationController.text.trim(),
        favoriteMusic: _favoriteMusicController.text.trim(),
        idealWeekend: _idealWeekendController.text.trim(),
        gender: _selectedGender,
        relationshipIntent: _selectedRelationshipIntent,
        interests: _selectedInterests,
        weekendAvailability: _weekendAvailability,
      );
      // Awaited: the provider rethrows when the profile row itself was not
      // written. Parts that failed are returned instead of thrown, so a saved
      // profile is never reported as a failed one.
      final warnings = await ref
          .read(weekendProvider.notifier)
          .updateProfile(updatedProfile);

      // Re-evaluate onboarding state so first-time signups continue into the
      // app. `refreshProfileSetup` reads the persisted row, so it only clears
      // once the write is actually visible server-side.
      await ref.read(authStateProvider.notifier).refreshProfileSetup();
      await ref.read(weekendProvider.notifier).loadCurrentUser();
      if (!mounted) return;

      if (ref.read(authStateProvider).needsProfileSetup) {
        // The write succeeded but the server still considers the profile
        // incomplete. Say what is missing instead of leaving the user on a
        // screen that silently refuses to advance.
        _showError(_incompleteReason());
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warnings.isEmpty
                ? 'Profile updated successfully!'
                : 'Profile saved, but ${warnings.join(' ')}',
          ),
          backgroundColor:
              warnings.isEmpty ? const Color(0xFF4CAF50) : Colors.orange,
          duration: Duration(seconds: warnings.isEmpty ? 3 : 6),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) _showError('Failed to save your profile. ${_readableSaveError(e)}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Explains exactly which mandatory field the server is still missing.
  String _incompleteReason() {
    final missing = <String>[];
    if (_nameController.text.trim().isEmpty) missing.add('Full Name');
    if (_cityController.text.trim().isEmpty) missing.add('City');
    if (missing.isEmpty) {
      return 'Your profile was saved, but the server still reports it as '
          'incomplete. Please contact support if this keeps happening.';
    }
    return 'Saved, but the server still needs: ${missing.join(' and ')}. '
        'Please fill ${missing.length == 1 ? 'it' : 'them'} in and tap Save again.';
  }

  void _showError(String message) {
    // Supabase/PostgREST failures arrive as raw `PostgrestException: ...`
    // text ("server error"); strip the class name so users see the actionable
    // message the repositories already mapped.
    final clean =
        message.replaceFirst(RegExp(r'^(StateError|Exception)\s*:\s*'), '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(clean),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final authId = _authUserId;
    if (authId == null) {
      _showError('You are not signed in, so the photo was not uploaded.');
      return;
    }
    if (_isUploadingPhoto) return;

    final file = await ImageOptimizer.pickAndOptimizeImage();    // A null file is either a user cancellation or a real picker/decode
    // failure. Only the latter is reported, and never as an upload success.
    if (file == null) {
      if (mounted && ImageOptimizer.lastError != null) {
        _showError(ImageOptimizer.lastError!);
      }
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final repo = ProfileRepository();
      // Throws unless BOTH the Storage object and the profile_photos row
      // were written. The returned value is the private storage path, never
      // a local file path.
      final path = await repo.uploadProfilePhoto(authId, bytes, true);
      if (path.isEmpty) {
        throw StateError('The photo could not be saved. Please try again.');
      }

      // Reload from the database so the avatar renders the real signed URL
      // rather than an optimistic local path.
      await ref.read(weekendProvider.notifier).refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo uploaded!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showError('Failed to upload photo. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    _educationController.dispose();
    _favoriteMusicController.dispose();
    _idealWeekendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(weekendProvider).currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130E20),
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF4B72),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFFFF4B72),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Photo
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFF4B72),
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 58,
                          backgroundImage: user.photos.isNotEmpty
                              ? NetworkImage(user.photos.first)
                              : null,
                          backgroundColor: const Color(0xFF2E244A),
                          child: user.photos.isEmpty
                              ? const Icon(
                                  Icons.person_rounded,
                                  size: 60,
                                  color: Colors.white38,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap:
                              _isUploadingPhoto ? null : _pickAndUploadPhoto,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF4B72),
                              shape: BoxShape.circle,
                            ),
                            child: _isUploadingPhoto
                                ? const Padding(
                                    padding: EdgeInsets.all(9),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Basic Info Section
                _buildSectionTitle('Basic Information'),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  label: 'Gender',
                  value: _selectedGender,
                  items: _availableGenders,
                  onChanged: (value) =>
                      setState(() => _selectedGender = value!),
                  icon: Icons.transgender_rounded,
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  label: 'Relationship Intent',
                  value: _selectedRelationshipIntent,
                  items: _availableRelationshipIntents,
                  onChanged: (value) =>
                      setState(() => _selectedRelationshipIntent = value!),
                  icon: Icons.favorite_rounded,
                ),
                const SizedBox(height: 24),

                // Location & Work
                _buildSectionTitle('Location & Work'),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _cityController,
                  label: 'City',
                  icon: Icons.location_city_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your city';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _occupationController,
                  label: 'Occupation',
                  icon: Icons.work_outline,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _educationController,
                  label: 'Education',
                  icon: Icons.school_outlined,
                ),
                const SizedBox(height: 24),

                // Bio
                _buildSectionTitle('About Me'),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _bioController,
                  label: 'Bio',
                  icon: Icons.info_outline,
                  maxLines: 4,
                  maxLength: 500,
                ),
                const SizedBox(height: 24),

                // Interests
                _buildSectionTitle('Interests'),
                const SizedBox(height: 8),
                Text(
                  'Select up to 10 interests',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableInterests.map((interest) {
                    final isSelected = _selectedInterests.contains(interest);
                    return FilterChip(
                      label: Text(interest),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (_selectedInterests.length < 10) {
                              _selectedInterests.add(interest);
                            }
                          } else {
                            _selectedInterests.remove(interest);
                          }
                        });
                      },
                      selectedColor: const Color(
                        0xFFFF4B72,
                      ).withValues(alpha: 0.3),
                      backgroundColor: const Color(0xFF2E244A),
                      checkmarkColor: const Color(0xFFFF4B72),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? const Color(0xFFFF9966)
                            : Colors.white.withValues(alpha: 0.8),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFFF4B72)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Weekend Availability
                _buildSectionTitle('Weekend Availability'),
                const SizedBox(height: 8),
                Text(
                  'When are you usually free for weekend plans?',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _weekendDays.map((day) {
                    final isSelected = _weekendAvailability[day] ?? false;
                    return FilterChip(
                      label: Text(day),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _weekendAvailability[day] = selected;
                        });
                      },
                      selectedColor: const Color(
                        0xFFFF4B72,
                      ).withValues(alpha: 0.3),
                      backgroundColor: const Color(0xFF2E244A),
                      checkmarkColor: const Color(0xFFFF4B72),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? const Color(0xFFFF9966)
                            : Colors.white.withValues(alpha: 0.8),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFFF4B72)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Personal Details
                _buildSectionTitle('Personal Details (Optional)'),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _favoriteMusicController,
                  label: 'Favorite Music',
                  icon: Icons.music_note_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _idealWeekendController,
                  label: 'Ideal Weekend',
                  icon: Icons.weekend_rounded,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: _inputDecoration(label, icon),
      validator: validator,
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    // A stored value that is not in the option list (an older label, a blank
    // placeholder row, or a value the CHECK constraint used to reject) makes
    // DropdownButtonFormField assert and render nothing at all — which reads
    // as a dead form. The selection is normalised in _loadCurrentProfile;
    // this is the last-resort fallback so the control always has a valid
    // initial value.
    final effective = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      initialValue: effective,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label, icon),
      dropdownColor: const Color(0xFF1C162E),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (value) => value == null ? 'Please select $label' : null,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      prefixIcon: Icon(icon, color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF1C162E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF4B72)),
      ),
      counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
    );
  }
}
