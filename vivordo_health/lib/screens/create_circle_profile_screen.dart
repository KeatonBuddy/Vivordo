import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../src/services/circle_profile_service.dart';
import '../theme/vivordo_theme.dart';

enum _UsernameStatus { idle, invalid, checking, available, taken, error }

class CreateCircleProfileScreen extends StatefulWidget {
  const CreateCircleProfileScreen({super.key, this.initialProfile});

  final CircleProfile? initialProfile;

  @override
  State<CreateCircleProfileScreen> createState() =>
      _CreateCircleProfileScreenState();
}

class _CreateCircleProfileScreenState extends State<CreateCircleProfileScreen> {
  static const _purple = Color(0xFF6250E8);

  final usernameController = TextEditingController();
  final bioController = TextEditingController();
  final picker = ImagePicker();
  Timer? usernameTimer;
  _UsernameStatus usernameStatus = _UsernameStatus.idle;
  Uint8List? photoBytes;
  String? photoName;
  bool saving = false;
  String? errorMessage;

  bool get editing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final initialProfile = widget.initialProfile;
    if (initialProfile != null) {
      usernameController.text = initialProfile.username;
      bioController.text = initialProfile.bio;
      usernameStatus = _UsernameStatus.available;
      return;
    }
    final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (displayName?.isNotEmpty == true) {
      final suggested = displayName!.replaceAll(RegExp(r'[^A-Za-z0-9_ ]'), '');
      usernameController.text = suggested.substring(
        0,
        suggested.length.clamp(0, 24),
      );
      _checkUsername(usernameController.text);
    }
  }

  @override
  void dispose() {
    usernameTimer?.cancel();
    usernameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  bool _validUsername(String value) {
    final clean = value.trim();
    return clean.length >= 3 &&
        clean.length <= 24 &&
        RegExp(r'^[A-Za-z0-9_ ]+$').hasMatch(clean);
  }

  void _usernameChanged(String value) {
    usernameTimer?.cancel();
    if (!_validUsername(value)) {
      setState(() => usernameStatus = _UsernameStatus.invalid);
      return;
    }
    setState(() => usernameStatus = _UsernameStatus.checking);
    usernameTimer = Timer(
      const Duration(milliseconds: 450),
      () => _checkUsername(value),
    );
  }

  Future<void> _checkUsername(String value) async {
    if (!_validUsername(value)) return;
    final checkedValue = value;
    try {
      final available = await CircleProfileService.isUsernameAvailable(value);
      if (!mounted || usernameController.text != checkedValue) return;
      setState(
        () => usernameStatus = available
            ? _UsernameStatus.available
            : _UsernameStatus.taken,
      );
    } catch (_) {
      if (!mounted || usernameController.text != checkedValue) return;
      setState(() => usernameStatus = _UsernameStatus.error);
    }
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Choose a profile picture',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              subtitle: const Text('Uses the front-facing camera'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 82,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        photoBytes = bytes;
        photoName = image.name;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = 'Could not open that photo: $error');
    }
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!_validUsername(usernameController.text)) {
      setState(() {
        usernameStatus = _UsernameStatus.invalid;
        errorMessage = 'Enter a username between 3 and 24 characters.';
      });
      return;
    }
    if (usernameStatus != _UsernameStatus.available) {
      await _checkUsername(usernameController.text);
      if (!mounted || usernameStatus != _UsernameStatus.available) return;
    }
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      if (editing) {
        await CircleProfileService.updateProfile(
          currentProfile: widget.initialProfile!,
          username: usernameController.text,
          bio: bioController.text,
          photoBytes: photoBytes,
          photoName: photoName,
        );
      } else {
        await CircleProfileService.createProfile(
          username: usernameController.text,
          bio: bioController.text,
          photoBytes: photoBytes,
          photoName: photoName,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } on CircleUsernameTakenException {
      if (!mounted) return;
      setState(() {
        usernameStatus = _UsernameStatus.taken;
        errorMessage = 'That username was just taken. Choose another one.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => errorMessage = editing
            ? 'Could not update your profile: $error'
            : 'Could not create your profile: $error',
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      title: Text(
        editing ? 'Edit Profile' : 'Create Profile',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: SafeArea(
      top: false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              editing
                  ? 'Update how your circle sees you.'
                  : 'Help your circle recognize you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.vivordoColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 26),
            Center(
              child: GestureDetector(
                onTap: saving ? null : _choosePhoto,
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 154,
                          height: 154,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.vivordoColors.cardMuted,
                            border: Border.all(
                              color: context.vivordoColors.card,
                              width: 3,
                            ),
                            image: photoBytes != null
                                ? DecorationImage(
                                    image: MemoryImage(photoBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : widget.initialProfile?.photoUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(
                                      widget.initialProfile!.photoUrl!,
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child:
                              photoBytes == null &&
                                  widget.initialProfile?.photoUrl == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: _purple,
                                  size: 78,
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 5,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _purple,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.vivordoColors.card,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: context.vivordoColors.shadow,
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      editing ? 'Change Photo' : 'Choose Photo',
                      style: const TextStyle(
                        color: _purple,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.vivordoColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.vivordoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FormLabel('DISPLAY NAME'),
                  const SizedBox(height: 9),
                  TextField(
                    controller: usernameController,
                    enabled: !saving,
                    maxLength: 24,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    onChanged: _usernameChanged,
                    decoration: _inputDecoration(
                      hint: 'Choose a display name',
                      suffix: _usernameSuffix(),
                    ).copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _usernameStatusText()),
                      Text(
                        '${usernameController.text.length} / 24',
                        style: TextStyle(
                          color: context.vivordoColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Your display name is unique and helps friends recognize you.',
                    style: TextStyle(
                      color: context.vivordoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _FormLabel('BIO'),
                  const SizedBox(height: 9),
                  TextField(
                    controller: bioController,
                    enabled: !saving,
                    maxLength: 120,
                    minLines: 4,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      hint: 'Tell your circle a little about yourself',
                    ).copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${bioController.text.length} / 120',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: saving ? null : _saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        editing ? 'Save Changes' : 'Create Profile',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: context.vivordoColors.textSecondary,
                  size: 15,
                ),
                const SizedBox(width: 7),
                Text(
                  'You can edit this anytime.',
                  style: TextStyle(
                    color: context.vivordoColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  InputDecoration _inputDecoration({required String hint, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.vivordoColors.textSecondary),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.vivordoColors.input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: context.vivordoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _purple, width: 1.5),
        ),
      );

  Widget? _usernameSuffix() => switch (usernameStatus) {
    _UsernameStatus.checking => const Padding(
      padding: EdgeInsets.all(14),
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    _UsernameStatus.available => const Icon(
      Icons.check_rounded,
      color: Color(0xFF12B76A),
    ),
    _UsernameStatus.taken || _UsernameStatus.invalid => const Icon(
      Icons.close_rounded,
      color: Colors.redAccent,
    ),
    _ => null,
  };

  Widget _usernameStatusText() {
    final (text, color) = switch (usernameStatus) {
      _UsernameStatus.available => ('Available', const Color(0xFF12B76A)),
      _UsernameStatus.taken => ('Username already taken', Colors.redAccent),
      _UsernameStatus.invalid => (
        'Use 3–24 letters, numbers, spaces, or _',
        Colors.redAccent,
      ),
      _UsernameStatus.checking => (
        'Checking availability…',
        context.vivordoColors.textSecondary,
      ),
      _UsernameStatus.error => (
        'Availability will be checked when saved',
        context.vivordoColors.textSecondary,
      ),
      _UsernameStatus.idle => ('', context.vivordoColors.textSecondary),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 12));
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.vivordoColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}
