import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recipe_keeper/models/app_user.dart';
import 'package:recipe_keeper/providers/auth_provider.dart';
import 'package:recipe_keeper/services/auth_service.dart';
import 'package:recipe_keeper/services/image_service.dart';
import 'package:recipe_keeper/utils/translations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:recipe_keeper/widgets/app_header.dart';
import 'package:recipe_keeper/widgets/app_bottom_nav.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_keeper/utils/app_theme.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final AppUser user;
  const EditProfileScreen({super.key, required this.user});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _displayNameController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  File? _imageFile;
  String? _currentImageUrl;
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _currentImageUrl = widget.user.photoURL;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

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
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              '${AppTranslations.getText(ref, 'error_selecting_image')}: $e',
            ),
          ),
        );
      }
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
                    leading: const Icon(
                      Icons.delete,
                      color: AppTheme.errorColor,
                    ),
                    title: Text(
                      AppTranslations.getText(ref, 'remove_image'),
                      style: const TextStyle(color: AppTheme.errorColor),
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

      // Handle password change if new password is provided
      if (_newPasswordController.text.isNotEmpty) {
        try {
          final authService = await ref.read(authServiceProvider.future);
          await authService.changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
        } catch (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${AppTranslations.getText(ref, 'error_changing_password')}: $e',
                ),
                backgroundColor: AppTheme.errorColor,
              ),
            );
            return; // Don't update profile if password change fails
          }
        }
      }

      // Update profile
      final authService = await ref.read(authServiceProvider.future);
      await authService.updateUserProfile(
        displayName: _displayNameController.text.trim(),
        photoURL: newPhotoUrl, // Pass the potentially updated URL
        preferences: widget.user.preferences, // Keep existing preferences
      );

      // Refresh user data locally - invalidation triggers refetch
      ref.invalidate(userDataProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTranslations.getText(ref, 'profile_updated_successfully'),
            ),
            backgroundColor: AppTheme.successColor,
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
            backgroundColor: AppTheme.errorColor,
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
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: AppTranslations.getText(ref, 'edit_profile'),
            onProfileTap: () => context.go('/profile'),
          ),
          Expanded(
            child: Form(
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
                            backgroundColor: const Color(
                              0xFFFF7E6B,
                            ).withValues(alpha: 0.1),
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
                                      color: AppTheme.primaryColor,
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
                                  color: AppTheme.lightAccentColor,
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
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondaryTextColor.withValues(
                              alpha: 0.1,
                            ),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(ref, 'name'),
                          labelStyle: const TextStyle(
                            color: AppTheme.textColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.secondaryFontFamily,
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
                    ),
                    const SizedBox(height: 16),
                    // Current Password Field
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondaryTextColor.withValues(
                              alpha: 0.1,
                            ),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _currentPasswordController,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(
                            ref,
                            'current_password',
                          ),
                          labelStyle: const TextStyle(
                            color: AppTheme.textColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.all(16),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppTheme.textColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureCurrentPassword =
                                    !_obscureCurrentPassword;
                              });
                            },
                          ),
                        ),
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.secondaryFontFamily,
                        ),
                        obscureText: _obscureCurrentPassword,
                        validator: (value) {
                          if (_newPasswordController.text.isNotEmpty &&
                              (value == null || value.isEmpty)) {
                            return AppTranslations.getText(
                              ref,
                              'current_password_required',
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // New Password Field
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondaryTextColor.withValues(
                              alpha: 0.1,
                            ),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(
                            ref,
                            'new_password',
                          ),
                          labelStyle: const TextStyle(
                            color: AppTheme.textColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.all(16),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppTheme.textColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                          ),
                        ),
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.secondaryFontFamily,
                        ),
                        obscureText: _obscureNewPassword,
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              value.length < 6) {
                            return AppTranslations.getText(
                              ref,
                              'password_too_short',
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Confirm Password Field
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondaryTextColor.withValues(
                              alpha: 0.1,
                            ),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: AppTranslations.getText(
                            ref,
                            'confirm_new_password',
                          ),
                          labelStyle: const TextStyle(
                            color: AppTheme.textColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.all(16),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppTheme.textColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontFamily: AppTheme.secondaryFontFamily,
                        ),
                        obscureText: _obscureConfirmPassword,
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              value != _newPasswordController.text) {
                            return AppTranslations.getText(
                              ref,
                              'passwords_do_not_match',
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: AppTheme.backgroundColor,
                          disabledBackgroundColor: AppTheme.primaryColor,
                          disabledForegroundColor: AppTheme.backgroundColor,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppTranslations.getText(ref, 'save_changes'),
                          style: const TextStyle(
                            color: AppTheme.lightAccentColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppTheme.secondaryFontFamily,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: -1),
    );
  }
}

// Add these translations if they don't exist
// 'profile_updated_successfully': 'Profile updated successfully!',
// 'error_updating_profile': 'Error updating profile',
// 'name_required': 'Please enter your name',

// Ensure ImageService has uploadProfileImage method or similar
// Ensure ImageService is provided via Riverpod (e.g., imageServiceProvider)
