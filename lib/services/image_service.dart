import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spoonit/config/env_config.dart';

// Define the provider
final imageServiceProvider = Provider<ImageService>((ref) => ImageService());

class ImageService {
  String get _proxyUrl => '${EnvConfig.apiBaseUrl}/proxy_image?url=';
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload a recipe image file to Firebase Storage
  Future<String> uploadRecipeImage(File imageFile, String userId) async {
    return _uploadImage(imageFile, userId, 'recipeImages');
  }

  // Upload a profile image file to Firebase Storage
  Future<String> uploadProfileImage(File imageFile, String userId) async {
    // Use a different path for profile images
    return _uploadImage(imageFile, userId, 'profileImages');
  }

  // Generic image upload function
  Future<String> _uploadImage(
    File imageFile,
    String userId,
    String folderName,
  ) async {
    final String fileName =
        '${userId}_${const Uuid().v4()}${path.extension(imageFile.path)}';
    final Reference storageRef = _storage.ref().child(
      '$folderName/$userId/$fileName',
    );

    final UploadTask uploadTask = storageRef.putFile(imageFile);
    final TaskSnapshot taskSnapshot = await uploadTask;

    return await taskSnapshot.ref.getDownloadURL();
  }

  // Get a CORS-safe URL for an image
  String getCorsProxiedUrl(String imageUrl) {
    if (!kIsWeb) {
      // On mobile, we don't need to proxy the image
      return imageUrl;
    }

    // Check if the URL is already a Firebase Storage URL (which has CORS configured)
    if (imageUrl.contains('firebasestorage.googleapis.com')) {
      return imageUrl;
    }

    // For external URLs, use our proxy
    developer.log('Proxying image URL: $imageUrl', name: 'ImageService');
    return '$_proxyUrl${Uri.encodeComponent(imageUrl)}';
  }
}

// Remove the old singleton instance if no longer needed elsewhere
// final imageService = ImageService();
