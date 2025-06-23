import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recipe_keeper/models/app_user.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/services/auth_service.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:recipe_keeper/utils/app_theme.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/screens/change_password_screen.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final AppUser user;
  const EditProfileScreen({super.key, required this.user});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _displayNameController;
  late TextEditingController _preferencesController;
  File? _imageFile;
  String? _currentImageUrl;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    _preferencesController = TextEditingController(
      text: widget.user.preferences['notes'] ?? '',
    );
    _currentImageUrl = widget.user.photoURL;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _currentImageUrl = null; // Clear network image if local is picked
        });
      }
    } catch (e) {
      // Handle errors, e.g., permissions
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppTranslations.getText(ref, 'error_selecting_image')}: $e',
          ),
        ),
      );
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(AppTranslations.getText(ref, 'gallery')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(AppTranslations.getText(ref, 'camera')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                if (_imageFile != null ||
                    (_currentImageUrl != null && _currentImageUrl!.isNotEmpty))
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: Text(
                      AppTranslations.getText(ref, 'remove_image'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      setState(() {
                        _imageFile = null;
                        _currentImageUrl =
                            ''; // Set to empty to signify removal
                      });
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? newPhotoUrl = widget.user.photoURL; // Start with current

      // If a new image was selected, upload it
      if (_imageFile != null) {
        final imageService = ref.read(
          imageServiceProvider,
        ); // Assuming ImageService is provided
        newPhotoUrl = await imageService.uploadProfileImage(
          _imageFile!,
          widget.user.uid,
        );
      } else if (_currentImageUrl != null && _currentImageUrl!.isEmpty) {
        // Handle removal if _currentImageUrl was explicitly set to empty
        newPhotoUrl = '';
      }

      // Prepare preferences update (example with simple 'notes' key)
      final Map<String, dynamic> updatedPreferences = Map.from(
        widget.user.preferences,
      );
      updatedPreferences['notes'] = _preferencesController.text.trim();

      // Update profile
      await ref
          .read(authServiceProvider)
          .updateUserProfile(
            displayName: _displayNameController.text.trim(),
            photoURL: newPhotoUrl, // Pass the potentially updated URL
            preferences: updatedPreferences, // Pass updated preferences
          );

      // Refresh user data locally - invalidation triggers refetch
      ref.invalidate(userDataProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'profile_updated_successfully'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppTranslations.getText(ref, 'error_updating_profile')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.getText(ref, 'edit_profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveProfile,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[200],
                      backgroundImage:
                          _imageFile != null
                              ? FileImage(_imageFile!)
                              : (_currentImageUrl != null &&
                                  _currentImageUrl!.isNotEmpty)
                              ? CachedNetworkImageProvider(
                                ImageService().getCorsProxiedUrl(
                                  _currentImageUrl!,
                                ),
                              ) // Use existing ImageService for CORS if needed
                              : null,
                      child:
                          (_imageFile == null &&
                                  (_currentImageUrl == null ||
                                      _currentImageUrl!.isEmpty))
                              ? const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey,
                              )
                              : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: AppTheme.primaryColor,
                        radius: 20,
                        child: IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _showImageSourceActionSheet,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: AppTranslations.getText(ref, 'name'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppTranslations.getText(
                      ref,
                      'name_required',
                    ); // Add translation if needed
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _preferencesController,
                decoration: InputDecoration(
                  labelText: AppTranslations.getText(ref, 'user_preferences'),
                  hintText: AppTranslations.getText(
                    ref,
                    'enter_preferences_placeholder',
                  ),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: Text(AppTranslations.getText(ref, 'change_password')),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

// Add these translations if they don't exist
// 'profile_updated_successfully': 'Profile updated successfully!',
// 'error_updating_profile': 'Error updating profile',
// 'name_required': 'Please enter your name',

// Ensure ImageService has uploadProfileImage method or similar
// Ensure ImageService is provided via Riverpod (e.g., imageServiceProvider)
