# SpoonIt

A Flutter application for storing, organizing, and sharing your favorite recipes.

## Features

- User authentication (sign up, login, password reset)
- Create, edit, and delete recipes
- Search recipes by title, ingredients, or tags
- Mark recipes as favorites
- Import recipes from URLs
- Take photos of recipes to digitize them
- User profiles with statistics
- Responsive design for mobile and web

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Firebase account
- Android Studio / VS Code with Flutter extensions

### Setup

1. Clone this repository
2. Navigate to the project directory:
   ```
   cd recipe_keeper
   ```
3. Install dependencies:
   ```
   flutter pub get
   ```

### Firebase Configuration

1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Enable Authentication with Email/Password
3. Create a Firestore database
4. Set up Firebase Storage
5. Update the Firebase configuration:
   - Update the `.firebaserc` file with your Firebase project ID
   - For Android: Download the `google-services.json` file and place it in `android/app/`
   - For iOS: Download the `GoogleService-Info.plist` file and place it in `ios/Runner/`
   - For Web: Update the Firebase configuration in `web/index.html`

### Firestore Security Rules

Add the following security rules to your Firestore database:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    match /recipes/{recipeId} {
      allow read: if request.auth != null && (resource.data.userId == request.auth.uid || resource.data.isPublic == true);
      allow write: if request.auth != null && (resource.data.userId == request.auth.uid || request.resource.data.userId == request.auth.uid);
      allow delete: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }
}
```

### Storage Security Rules

Add the following security rules to your Firebase Storage:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /recipeImages/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    match /profileImages/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Running the App

### Development

```
flutter run
```

### Web Deployment

1. Build the web version:
   ```
   flutter build web
   ```

2. Deploy to Firebase Hosting:
   ```
   firebase deploy --only hosting
   ```

## Architecture

- **Models**: Data models for the application
- **Providers**: State management using Riverpod
- **Screens**: UI screens for different parts of the app
- **Services**: Business logic and Firebase interactions
- **Widgets**: Reusable UI components
- **Utils**: Helper functions and utilities

## License

This project is licensed under the MIT License - see the LICENSE file for details.
