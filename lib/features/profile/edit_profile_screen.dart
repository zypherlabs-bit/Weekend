import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../../models/profile_schema.dart';
import '../../providers/auth_provider.dart';
import '../../providers/weekend_provider.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/profile_save_error.dart';
import '../../services/image_optimizer.dart';

/// Edit Profile — Weekend's full profile builder.
///
/// Structure follows what mature dating apps ask for, in the order a user
/// actually fills a profile in:
///
///   1. Photos      (add / reorder / set primary / delete, minimum enforced)
///   2. Basics      (name, birthday, gender, city, intent)
///   3. About       (bio, occupation, education, music, ideal weekend)
///   4. Prompts     (Weekend's own question catalogue)
///   5. Interests   (categorised multi-select)
///   6. Lifestyle   (smoking / drinking / exercise / pets / children / languages)
///
/// Save flow (never navigates away on failure, never reports a false success):
///
///   validate -> auth -> photo minimum -> upload pending photos ->
///   profile fields -> prompts -> interests -> preferences ->
///   confirm server -> refresh local -> navigate
///
/// Every stage that fails keeps the user on this screen with an actionable
/// message and a working retry.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basics
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _occupationController = TextEditingController();
  final _educationController = TextEditingController();
  final _favoriteMusicController = TextEditingController();
  final _idealWeekendController = TextEditingController();

  String _selectedGender = 'Man';
  String _selectedRelationshipIntent = 'Dating & Weekend Plans';
  DateTime? _dateOfBirth;

  // Prompts: id -> answer draft.
  final Map<String, TextEditingController> _promptControllers = {};

  // Interests
  Set<String> _selectedInterests = {};

  // Lifestyle
  final Map<String, String?> _lifestyle = {};
  final List<String> _languages = [];

  // Weekend availability
  Map<String, bool> _weekendAvailability = {'Saturday': false, 'Sunday': false};

  // Photos
  final ProfileRepository _repo = ProfileRepository();
  List<ProfilePhotoRecord> _photos = const [];
  int _minPhotos = ProfileSchema.minimumPhotos;
  int _maxPhotos = ProfileSchema.maximumPhotos;
  bool _loadingPhotos = true;

  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadAll();
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
    for (final c in _promptControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Load the profile, its photos and the server's photo limits together.
  Future<void> _loadAll() async {
    setState(() {
      _loadError = null;
      _loadingPhotos = true;
    });
    try {
      await ref.read(weekendProvider.notifier).loadCurrentUser();
      final user = ref.read(weekendProvider).currentUser;
      final authId = _authUserId;

      List<ProfilePhotoRecord> photos = const [];
      int minPhotos = ProfileSchema.minimumPhotos;
      int maxPhotos = ProfileSchema.maximumPhotos;
      if (authId != null) {
        // Limits first: the UI must know the real minimum before it decides
        // whether to block a save.
        minPhotos = await _repo.minimumPhotos();
        maxPhotos = await _repo.maximumPhotos();
        photos = await _repo.fetchProfilePhotoRecords(authId);
      }
      if (!mounted) return;

      _nameController.text = user.name;
      _bioController.text = user.bio;
      _cityController.text = user.city;
      _occupationController.text = user.occupation;
      _educationController.text = user.education;
      _favoriteMusicController.text = user.favoriteMusic;
      _idealWeekendController.text = user.idealWeekend;

      _selectedGender = ProfileSchema.genders.contains(user.gender)
          ? user.gender
          : ProfileSchema.genders.first;
      _selectedRelationshipIntent =
          ProfileSchema.relationshipIntents.contains(user.relationshipIntent)
          ? user.relationshipIntent
          : ProfileSchema.relationshipIntents.last;

      _selectedInterests = user.interests.toSet();
      _languages.addAll(user.languages);
      _weekendAvailability = user.weekendAvailability.isEmpty
          ? {'Saturday': false, 'Sunday': false}
          : Map<String, bool>.from(user.weekendAvailability);

      _lifestyle
        ..clear()
        ..addAll({
          'smoking': user.smoking,
          'drinking': user.drinking,
          'exercise': user.exercise,
          'pets': user.pets,
          'children': user.children,
        });

      // Seed a controller for EVERY catalogue prompt so switching sections
      // never loses a half-typed answer.
      for (final id in ProfileSchema.allPromptIds) {
        if (_promptControllers.containsKey(id)) continue;
        final existing = user.prompts
            .where((p) => p.id == id)
            .map((p) => p.answer)
            .firstOrNull;
        _promptControllers[id] = TextEditingController(text: existing ?? '');
      }

      setState(() {
        _photos = photos;
        _minPhotos = minPhotos.clamp(1, 10);
        _maxPhotos = maxPhotos.clamp(1, 10);
        _loadingPhotos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPhotos = false;
        _loadError = _readableSaveError(e);
      });
    }
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
  String _readableSaveError(Object e) {
    if (e is ProfileSaveException) return e.message;
    final text = e
        .toString()
        .replaceFirst(RegExp(r'^(StateError|Exception)\s*:\s*'), '')
        .replaceFirst('Bad state: ', '');
    final lower = text.toLowerCase();
    if (lower.contains('too many languages')) {
      return 'Please choose up to 8 languages.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timeout')) {
      return 'Network error. Check your connection and try again.';
    }
    return text;
  }

  void _showError(String message) {
    final clean = message.replaceFirst(
      RegExp(r'^(StateError|Exception)\s*:\s*'),
      '',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(clean),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ------------------------------------------------------------------ SAVE
  // Ordered exactly like the product requirement: nothing navigates away until
  // Supabase has confirmed every stage.

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    // 1. Client-side validation.
    if (!_formKey.currentState!.validate()) {
      setState(() => _saveError = 'Please fix the highlighted fields.');
      return;
    }

    // 2. Authentication.
    final authId = _authUserId;
    if (authId == null) {
      setState(() => _saveError = 'You are not signed in, so nothing was saved.');
      return;
    }

    // 3. Minimum photos.
    if (_photos.length < _minPhotos) {
      setState(
        () => _saveError =
            'Add at least $_minPhotos photos before saving. '
            'You have ${_photos.length}.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      // Build the profile exactly as the form shows it.
      final prompts = <ProfilePrompt>[
        for (final entry in _promptControllers.entries)
          if (entry.value.text.trim().isNotEmpty)
            ProfilePrompt(
              id: entry.key,
              prompt:
                  ProfileSchema.promptById(entry.key)?.question ?? 'About me',
              answer: entry.value.text.trim(),
            ),
      ];

      final current = ref.read(weekendProvider).currentUser;
      final updated = current.copyWith(
        name: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        city: _cityController.text.trim(),
        occupation: _occupationController.text.trim(),
        education: _educationController.text.trim(),
        favoriteMusic: _favoriteMusicController.text.trim(),
        idealWeekend: _idealWeekendController.text.trim(),
        gender: _selectedGender,
        relationshipIntent: _selectedRelationshipIntent,
        interests: _selectedInterests.toList(),
        languages: _languages,
        prompts: prompts,
        smoking: _lifestyle['smoking'],
        drinking: _lifestyle['drinking'],
        exercise: _lifestyle['exercise'],
        pets: _lifestyle['pets'],
        children: _lifestyle['children'],
        weekendAvailability: _weekendAvailability,
      );

      // 4-8. Fields, prompts, interests and preferences.
      //
      // Awaited and NOT swallowed: the provider rethrows when the profile row
      // itself was not written, and returns the parts that failed as warnings
      // so a genuinely-saved profile is never reported as failed.
      final warnings = await ref
          .read(weekendProvider.notifier)
          .updateProfile(updated);

      // Date of birth is written separately: the model carries a derived age,
      // not the date, and the picker is the authority for the real value.
      // Written AFTER the main save so the profile row exists first - the
      // repository rejects a zero-row update rather than pretending it landed.
      if (_dateOfBirth != null) {
        try {
          await _repo.updateDateOfBirth(_dateOfBirth!);
        } on ProfileSaveException catch (e) {
          if (e.failure == ProfileSaveFailure.validation) {
            // A refusal the user can act on (under 18, out of range).
            setState(() => _saveError = e.message);
            return;
          }
          rethrow;
        }
      }

      // 9. Confirm with the server rather than trusting the local write.
      await ref.read(authStateProvider.notifier).refreshProfileSetup();
      await ref.read(weekendProvider.notifier).loadCurrentUser();
      if (!mounted) return;

      if (ref.read(authStateProvider).needsProfileSetup) {
        setState(() => _saveError = _incompleteReason());
        return;
      }

      // 10. Success. Only now do we leave the screen.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warnings.isEmpty
                ? 'Profile saved.'
                : 'Profile saved, but ${warnings.join(' ')}',
          ),
          backgroundColor: warnings.isEmpty
              ? const Color(0xFF4CAF50)
              : Colors.orange,
          duration: Duration(seconds: warnings.isEmpty ? 3 : 6),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      // Stays on the screen. No navigation, no false success.
      if (mounted) {
        setState(() => _saveError = _readableSaveError(e));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Explains exactly which mandatory field the server is still missing.
  String _incompleteReason() {
    final missing = <String>[];
    if (_nameController.text.trim().isEmpty) missing.add('your name');
    if (_cityController.text.trim().isEmpty) missing.add('your city');
    if (missing.isEmpty) {
      return 'Your profile was saved, but the server still reports it as '
          'incomplete. Please contact support if this keeps happening.';
    }
    return 'Saved, but the server still needs ${missing.join(' and ')}. '
        'Please add ${missing.length == 1 ? 'it' : 'them'} and save again.';
  }

  // ----------------------------------------------------------------- PHOTOS

  Future<void> _addPhoto() async {
    final authId = _authUserId;
    if (authId == null) {
      _showError('You are not signed in, so no photo was uploaded.');
      return;
    }
    if (_photos.length >= _maxPhotos) {
      _showError('You already have the maximum of $_maxPhotos photos.');
      return;
    }

    // A null file is a user cancellation or a picker/decode failure. Only the
    // latter is reported, and never as an upload success.
    final file = await ImageOptimizer.pickAndOptimizeImage();
    if (file == null) {
      if (mounted && ImageOptimizer.lastError != null) {
        _showError(ImageOptimizer.lastError!);
      }
      return;
    }

    setState(() => _loadingPhotos = true);
    try {
      final bytes = await file.readAsBytes();
      // Throws unless BOTH the Storage object and the profile_photos row were
      // written. Returns the private storage path, never a local file path.
      await _repo.uploadProfilePhoto(authId, bytes, true);
      if (!mounted) return;
      final fresh = await _repo.fetchProfilePhotoRecords(authId);
      if (!mounted) return;
      setState(() => _photos = fresh);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo added.'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      // The tile stays absent so the user can retry; nothing is faked.
      if (mounted) {
        _showError('Could not add that photo. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  /// Replace a photo at [index]: the new image takes that exact slot.
  ///
  /// Order matters: add first, then reorder, then delete the old row. Doing it
  /// the other way round would leave a hole in the profile if the upload
  /// failed after the delete.
  Future<void> _replacePhoto(int index) async {
    final authId = _authUserId;
    if (authId == null) return;
    final current = _photos[index];
    if (_photos.length >= _maxPhotos) {
      _showError(
        'You already have the maximum of $_maxPhotos photos. '
        'Remove one before replacing it.',
      );
      return;
    }

    final file = await ImageOptimizer.pickAndOptimizeImage();
    if (file == null) {
      if (mounted && ImageOptimizer.lastError != null) {
        _showError(ImageOptimizer.lastError!);
      }
      return;
    }

    setState(() => _loadingPhotos = true);
    try {
      final bytes = await file.readAsBytes();
      await _repo.uploadProfilePhoto(authId, bytes, false);
      if (!mounted) return;

      var fresh = await _repo.fetchProfilePhotoRecords(authId);
      // The new row lands last; move it into the slot the old one occupied.
      final newIds = <String>[
        ...fresh.take(index).map((p) => p.id),
        fresh.last.id,
        ...fresh
            .sublist(0, fresh.length - 1)
            .skip(index)
            .map((p) => p.id),
      ];
      await _repo.reorderPhotos(newIds);
      fresh = await _repo.fetchProfilePhotoRecords(authId);

      // Now the old row can go.
      if (current.storagePath.isNotEmpty) {
        try {
          await _repo.deletePhoto(current);
        } catch (e) {
          debugPrint('replaced photo, old row cleanup failed: $e');
        }
      }
      if (!mounted) return;
      final refreshed = await _repo.fetchProfilePhotoRecords(authId);
      if (!mounted) return;
      setState(() => _photos = refreshed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo replaced.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not replace that photo. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  /// Move the photo at [from] to [to] and persist the whole new order.
  ///
  /// The local list is only updated AFTER the server confirms, so a failed
  /// reorder leaves the tiles in their real order rather than showing a
  /// rearrangement that was never saved.
  Future<void> _movePhoto(int from, int to) async {
    final authId = _authUserId;
    if (authId == null) return;
    if (from == to || to < 0 || to >= _photos.length) return;

    final reordered = List<ProfilePhotoRecord>.from(_photos);
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);

    setState(() => _loadingPhotos = true);
    try {
      await _repo.reorderPhotos(reordered.map((p) => p.id).toList());
      if (!mounted) return;
      final fresh = await _repo.fetchProfilePhotoRecords(authId);
      if (!mounted) return;
      setState(() => _photos = fresh);
    } catch (e) {
      if (mounted) {
        _showError('Could not reorder photos. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  /// Make the photo at [index] the primary (first) one.
  Future<void> _makePrimary(int index) async {
    final authId = _authUserId;
    if (authId == null) return;
    if (_photos[index].isPrimary && index == 0) return;

    setState(() => _loadingPhotos = true);
    try {
      await _repo.setPrimaryPhoto(_photos[index].id);
      if (!mounted) return;
      final fresh = await _repo.fetchProfilePhotoRecords(authId);
      if (!mounted) return;
      setState(() => _photos = fresh);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Main photo updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not set the main photo. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  /// Delete the photo at [index].
  ///
  /// Refused server-side when it would drop the profile below the minimum, and
  /// the UI disables the action before the call so the user is not baited into
  /// an error they cannot act on.
  Future<void> _deletePhoto(int index) async {
    final authId = _authUserId;
    if (authId == null) return;
    final photo = _photos[index];
    if (_photos.length - 1 < _minPhotos) {
      _showError(
        'You need at least $_minPhotos photos. '
        'Add another before removing this one.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Remove photo?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This deletes the photo from your profile. You cannot undo it.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loadingPhotos = true);
    try {
      await _repo.deletePhoto(photo);
      if (!mounted) return;
      final fresh = await _repo.fetchProfilePhotoRecords(authId);
      if (!mounted) return;
      setState(() => _photos = fresh);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not remove that photo. ${_readableSaveError(e)}');
      }
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final completeness = _completeness();
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF130E20),
        elevation: 0,
        leading: IconButton(
          onPressed: _isSaving ? null : () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _completionCard(completeness),
            const SizedBox(height: 20),
            _photosSection(),
            const SizedBox(height: 24),
            _basicsSection(),
            const SizedBox(height: 24),
            _aboutSection(),
            const SizedBox(height: 24),
            _promptsSection(),
            const SizedBox(height: 24),
            _interestsSection(),
            const SizedBox(height: 24),
            _lifestyleSection(),
            const SizedBox(height: 24),
            _availabilitySection(),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _saveButton(),
    );
  }

  Widget _saveButton() {
    final photosOk = _photos.length >= _minPhotos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FloatingActionButton.extended(
          // Disabled only for the two states where a save provably cannot
          // succeed: in-flight, and the photo minimum not met.
          onPressed: (_isSaving || !photosOk) ? null : _saveProfile,
          backgroundColor: photosOk
              ? const Color(0xFFFF4B72)
              : Colors.white.withValues(alpha: 0.12),
          foregroundColor: photosOk ? Colors.white : Colors.white38,
          icon: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _isSaving
                ? 'Saving...'
                : photosOk
                ? 'Save profile'
                : 'Add $_minPhotos photos to save',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  /// Which mandatory pieces are still missing.
  ({int done, int total, List<String> missing}) _completeness() {
    final missing = <String>[];
    if (_nameController.text.trim().isEmpty) missing.add('Name');
    if (_cityController.text.trim().isEmpty) missing.add('City');
    if (_dateOfBirth == null) missing.add('Birthday');
    if (_photos.length < _minPhotos) {
      missing.add('$_minPhotos photos');
    }
    const total = 4;
    return (
      done: (total - missing.length).clamp(0, total),
      total: total,
      missing: missing,
    );
  }

  Widget _completionCard(({int done, int total, List<String> missing}) c) {
    final complete = c.missing.isEmpty;
    final fraction = c.done / c.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (complete ? const Color(0xFF4CAF50) : const Color(0xFFFF9966))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (complete ? const Color(0xFF4CAF50) : const Color(0xFFFF9966))
              .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.verified_rounded : Icons.radar_rounded,
                color: complete
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF9966),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  complete
                      ? 'Your profile is ready'
                      : '${c.done} of ${c.total} complete',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                complete
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF9966),
              ),
            ),
          ),
          if (c.missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Still needed: ${c.missing.join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _saveError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Could not load your profile: $_loadError',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        required ? '$text *' : text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ PHOTOS

  Widget _photosSection() {
    final remaining = _minPhotos - _photos.length;
    return _sectionCard(
      title: 'Photos',
      subtitle: remaining > 0
          ? 'Add $remaining more. The first photo is what people see first.'
          : 'Tap a photo for options. The first one leads your profile.',
      children: [
        if (_loadingPhotos)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Color(0xFFFF4B72)),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _photos.length; i++) _photoTile(i),
              if (_photos.length < _maxPhotos)
                _addPhotoTile,
            ],
          ),
        if (!_loadingPhotos && _photos.length < _minPhotos) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekend needs at least $_minPhotos photos before your '
                  'profile can appear in Discover.',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _photoTile(int index) {
    final photo = _photos[index];
    final canDelete = _photos.length - 1 >= _minPhotos;
    return GestureDetector(
      onTap: () => _showPhotoActions(index, canDelete),
      child: SizedBox(
        width: 104,
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: photo.url == null
                  ? Container(
                      color: const Color(0xFF2E244A),
                      child: const Icon(
                        Icons.image_not_supported_rounded,
                        color: Colors.white38,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: photo.url!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF2E244A),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFF4B72),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF2E244A),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                        ),
                      ),
                    ),
            ),
            // Position badge: shows the user's chosen order at a glance.
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (index == 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4B72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'MAIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget get _addPhotoTile {
    return GestureDetector(
      onTap: _addPhoto,
      child: SizedBox(
        width: 104,
        height: 140,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_a_photo_rounded,
                color: Color(0xFFFF4B72),
                size: 28,
              ),
              SizedBox(height: 8),
              Text(
                'Add',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-photo actions: reorder, make primary, replace, delete.
  Future<void> _showPhotoActions(int index, bool canDelete) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C162E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded),
              title: const Text('Move earlier'),
              subtitle: Text('Position ${index + 1}'),
              enabled: index > 0,
              onTap: () {
                Navigator.pop(sheetContext);
                _movePhoto(index, index - 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded),
              title: const Text('Move later'),
              subtitle: Text('Position ${index + 1} of ${_photos.length}'),
              enabled: index < _photos.length - 1,
              onTap: () {
                Navigator.pop(sheetContext);
                _movePhoto(index, index + 1);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.star_rounded,
                color: Color(0xFFFF4B72),
              ),
              title: const Text('Make this my main photo'),
              enabled: index != 0,
              onTap: () {
                Navigator.pop(sheetContext);
                _makePrimary(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Replace photo'),
              subtitle: const Text('Keeps this position in your profile'),
              onTap: () {
                Navigator.pop(sheetContext);
                _replacePhoto(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text(
                'Delete photo',
                style: TextStyle(color: Colors.red),
              ),
              // Disabled with the reason shown, rather than letting the user
              // tap into an error they cannot act on.
              subtitle: canDelete
                  ? null
                  : Text(
                      'You need at least $_minPhotos photos',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
              enabled: canDelete,
              onTap: () {
                Navigator.pop(sheetContext);
                _deletePhoto(index);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ BASICS

  Widget _basicsSection() {
    return _sectionCard(
      title: 'Basics',
      subtitle: 'The first things people read on your card.',
      children: [
        _fieldLabel('First name', required: true),
        TextFormField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('What should people call you?'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v ?? '').trim().isEmpty
              ? 'Your name is required'
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Age', required: true),
        _birthdayPicker(),
        const SizedBox(height: 12),
        _fieldLabel('Gender'),
        _choiceChips(
          options: ProfileSchema.genders,
          selected: _selectedGender,
          onSelect: (v) => setState(() => _selectedGender = v),
        ),
        const SizedBox(height: 12),
        _fieldLabel('City', required: true),
        TextFormField(
          controller: _cityController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Where are you based?'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v ?? '').trim().isEmpty
              ? 'Your city is required'
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Looking for'),
        _choiceChips(
          options: ProfileSchema.relationshipIntents,
          selected: _selectedRelationshipIntent,
          onSelect: (v) => setState(() => _selectedRelationshipIntent = v),
        ),
      ],
    );
  }

  Widget _birthdayPicker() {
    final dob = _dateOfBirth;
    final age = dob == null ? null : DateTime.now().difference(dob).inDays ~/ 365;
    // Weekend is an adult-only product: the picker caps the lower bound at 18,
    // because the hard age filter in `search_profiles` starts there.
    return InkWell(
      onTap: _pickBirthday,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDecoration(
          dob == null
              ? 'Select your date of birth'
              : 'Showing as ${age ?? 0}',
        ).copyWith(
          suffixIcon: const Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: Colors.white38,
          ),
        ),
        child: Text(
          dob == null
              ? 'Select your date of birth'
              : '${dob.day}/${dob.month}/${dob.year}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select your date of birth',
    );
    if (picked == null) return;
    setState(() => _dateOfBirth = picked);
  }

  // ------------------------------------------------------------------- ABOUT

  Widget _aboutSection() {
    return _sectionCard(
      title: 'About you',
      subtitle: 'A few lines that sound like you, not a template.',
      children: [
        _fieldLabel('Bio'),
        TextFormField(
          controller: _bioController,
          maxLines: 5,
          maxLength: 500,
          style: const TextStyle(color: Colors.white, height: 1.4),
          decoration: _inputDecoration('Tell people what makes you, you.'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Work'),
        TextFormField(
          controller: _occupationController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('What do you do?'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        _fieldLabel('Education'),
        TextFormField(
          controller: _educationController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Where did you study?'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        _fieldLabel('Music you are into'),
        TextFormField(
          controller: _favoriteMusicController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Artists, genres, live shows'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        _fieldLabel('Your ideal weekend'),
        TextFormField(
          controller: _idealWeekendController,
          maxLines: 3,
          maxLength: 300,
          style: const TextStyle(color: Colors.white, height: 1.4),
          decoration: _inputDecoration('How do you actually spend it?'),
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- PROMPTS

  Widget _promptsSection() {
    final answered = _promptControllers.values
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    return _sectionCard(
      title: 'Prompts',
      subtitle: '$answered of ${ProfileSchema.maxPrompts} shown on your card. '
          'Answer as many as feel like you.',
      children: [
        for (final section in ProfileSchema.promptSections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: Row(
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Color(0xFFFF9966),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.subtitle,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final prompt in section.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _promptField(prompt.id, prompt.question, prompt.hint),
            ),
        ],
        _promptCountNotice(answered),
      ],
    );
  }

  Widget _promptField(String id, String question, String hint) {
    final controller = _promptControllers[id];
    if (controller == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                question,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 16),
              color: Colors.white38,
              // Present so an answer can be cleared from anywhere in the form.
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => setState(controller.clear),
            ),
          ],
        ),
        Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 300,
          style: const TextStyle(color: Colors.white, height: 1.4),
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration('Your answer'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  /// Tells the user which prompts actually reach the card.
  ///
  /// Silently dropping answers past the limit would look like data loss, so the
  /// cap is stated up front rather than discovered after saving.
  Widget _promptCountNotice(int answered) {
    if (answered <= ProfileSchema.maxPrompts) {
      return const SizedBox.shrink();
    }
    final hidden = answered - ProfileSchema.maxPrompts;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Text(
        'You have answered $answered. Only the first '
        '${ProfileSchema.maxPrompts} are shown on your profile card, so '
        '$hidden ${hidden == 1 ? 'answer is' : 'answers are'} hidden.',
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
      ),
    );
  }

  // --------------------------------------------------------------- INTERESTS

  Widget _interestsSection() {
    return _sectionCard(
      title: 'Interests',
      subtitle: '${_selectedInterests.length} selected. Pick what you would '
          'actually talk about.',
      children: [
        for (final entry in ProfileSchema.interestCategories.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final interest in entry.value)
                _interestChip(interest),
            ],
          ),
        ],
      ],
    );
  }

  Widget _interestChip(String interest) {
    final selected = _selectedInterests.contains(interest);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedInterests.remove(interest);
        } else {
          _selectedInterests.add(interest);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF4B72).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF4B72)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: Color(0xFFFF4B72),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              interest,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- LIFESTYLE

  Widget _lifestyleSection() {
    return _sectionCard(
      title: 'Lifestyle',
      subtitle: 'Straight answers save everyone time. Skip anything you would '
          'rather not say.',
      children: [
        for (final field in ProfileSchema.lifestyleFields) ...[
          _fieldLabel(field.question),
          _lifestyleChips(field),
          const SizedBox(height: 12),
        ],
        _fieldLabel('Languages you speak'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lang in ProfileSchema.suggestedLanguages)
              _languageChip(lang),
            ActionChip(
              label: const Text(
                '+ Other',
                style: TextStyle(color: Color(0xFFFF9966), fontSize: 13),
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              side: const BorderSide(color: Color(0xFFFF9966)),
              onPressed: _addCustomLanguage,
            ),
          ],
        ),
      ],
    );
  }

  Widget _lifestyleChips(LifestyleField field) {
    final current = _lifestyle[field.column];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in field.options)
          GestureDetector(
            onTap: () => setState(() {
              // Tapping the selected option clears it: the column goes back to
              // NULL, which the database CHECK allows.
              _lifestyle[field.column] = current == option.value
                  ? null
                  : option.value;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: current == option.value
                    ? const Color(0xFFFF9966).withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: current == option.value
                      ? const Color(0xFFFF9966)
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  color: current == option.value
                      ? Colors.white
                      : Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _languageChip(String language) {
    final selected = _languages.contains(language);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _languages.remove(language);
        } else if (_languages.length < 8) {
          _languages.add(language);
        } else {
          _showError('You can choose up to 8 languages.');
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4CAF50).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF4CAF50)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          language,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> _addCustomLanguage() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text(
          'Add a language',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Konkani',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    final language = value?.trim() ?? '';
    if (language.isEmpty || !mounted) return;
    if (_languages.contains(language)) return;
    if (_languages.length >= 8) {
      _showError('You can choose up to 8 languages.');
      return;
    }
    setState(() => _languages.add(language));
  }

  // ------------------------------------------------------------ AVAILABILITY

  Widget _availabilitySection() {
    return _sectionCard(
      title: 'Weekend availability',
      subtitle: 'When are you actually free?',
      children: [
        Wrap(
          spacing: 10,
          children: [
            for (final day in const ['Saturday', 'Sunday'])
              FilterChip(
                label: Text(day),
                selected: _weekendAvailability[day] ?? false,
                selectedColor: const Color(0xFFFF4B72),
                checkmarkColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                labelStyle: TextStyle(
                  color: (_weekendAvailability[day] ?? false)
                      ? Colors.white
                      : Colors.white70,
                ),
                onSelected: (v) => setState(() {
                  _weekendAvailability[day] = v;
                }),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ SHARED

  InputDecoration _inputDecoration(String hint, {String? errorText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
      errorText: errorText,
      counterStyle: const TextStyle(color: Colors.white30, fontSize: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF4B72), width: 1.5),
      ),
    );
  }

  Widget _choiceChips({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () => onSelect(option),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: selected == option
                    ? const Color(0xFFFF4B72).withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected == option
                      ? const Color(0xFFFF4B72)
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                option,
                style: TextStyle(
                  color: selected == option ? Colors.white : Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
