import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final int recipeCount;
  final int favoriteCount;
  final int sharedCount;
  final List<String> favoriteRecipes;
  final Map<String, dynamic> preferences;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    required this.createdAt,
    required this.lastLoginAt,
    this.recipeCount = 0,
    this.favoriteCount = 0,
    this.sharedCount = 0,
    this.favoriteRecipes = const [],
    this.preferences = const {},
  });

  // Add id getter to match what's being used in the code
  String get id => uid;

  // Create a copy with updated fields
  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    int? recipeCount,
    int? favoriteCount,
    int? sharedCount,
    List<String>? favoriteRecipes,
    Map<String, dynamic>? preferences,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      recipeCount: recipeCount ?? this.recipeCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      sharedCount: sharedCount ?? this.sharedCount,
      favoriteRecipes: favoriteRecipes ?? this.favoriteRecipes,
      preferences: preferences ?? this.preferences,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'recipeCount': recipeCount,
      'favoriteCount': favoriteCount,
      'sharedCount': sharedCount,
      'favoriteRecipes': favoriteRecipes,
      'preferences': preferences,
    };
  }

  // Create from Firestore document
  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      photoURL: data['photoURL'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recipeCount: data['recipeCount'] ?? 0,
      favoriteCount: data['favoriteCount'] ?? 0,
      sharedCount: data['sharedCount'] ?? 0,
      favoriteRecipes: List<String>.from(data['favoriteRecipes'] ?? []),
      preferences: Map<String, dynamic>.from(data['preferences'] ?? {}),
    );
  }

  @override
  String toString() {
    return 'AppUser(uid: $uid, email: $email, displayName: $displayName)';
  }
} 
