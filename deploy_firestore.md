# Firestore Deployment Guide

## Step 1: Deploy the Web App

First, deploy just the web app without Firestore rules:

```bash
# Build the Flutter web app
flutter build web

# Deploy to Firebase hosting
firebase deploy --only hosting
```

## Step 2: Enable Firestore API

You need to enable the Firestore API for your project:

1. Go to: https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=recipekeeper-d436a
2. Click the "Enable" button
3. Wait a few minutes for the API to be enabled

## Step 3: Create Firestore Database

If you haven't created a Firestore database yet:

1. Go to: https://console.firebase.google.com/project/recipekeeper-d436a/firestore
2. Click "Create database"
3. Choose "Start in production mode"
4. Select a location close to your users
5. Click "Enable"

## Step 4: Update firebase.json and Deploy Firestore Rules

After enabling the Firestore API, update your firebase.json file to include Firestore rules:

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  },
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "flutter": {
    "platforms": {
      "android": {
        "default": {
          "projectId": "recipekeeper-d436a",
          "appId": "1:682017024777:android:60351fed0ebb4eab8601d8",
          "fileOutput": "android/app/google-services.json"
        }
      },
      "dart": {
        "lib/firebase_options.dart": {
          "projectId": "recipekeeper-d436a",
          "configurations": {
            "android": "1:682017024777:android:60351fed0ebb4eab8601d8",
            "ios": "1:682017024777:ios:c48cb71f25c5d4608601d8",
            "macos": "1:682017024777:ios:c48cb71f25c5d4608601d8",
            "web": "1:682017024777:web:b53ab4e1120a5e2f8601d8",
            "windows": "1:682017024777:web:e0dfe13f7c1c26368601d8"
          }
        }
      }
    }
  }
}
```

Then deploy the Firestore rules:

```bash
# Deploy Firestore rules and indexes
firebase deploy --only firestore
```

## Step 5: Verify Everything Works

1. Test the web app to make sure it loads correctly
2. Test user registration to ensure Firestore operations work
3. Test recipe creation and management 