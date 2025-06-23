#!/bin/bash

# Build the Flutter web app
echo "Building Flutter web app..."
flutter build web

# Deploy to Firebase hosting
echo "Deploying to Firebase hosting..."
firebase deploy --only hosting

# Remind about Firestore API
echo ""
echo "IMPORTANT: Before deploying Firestore rules, you need to enable the Firestore API:"
echo "1. Go to: https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=recipekeeper-d436a"
echo "2. Click the 'Enable' button"
echo "3. Wait a few minutes for the API to be enabled"
echo ""
echo "If you haven't created a Firestore database yet:"
echo "1. Go to: https://console.firebase.google.com/project/recipekeeper-d436a/firestore"
echo "2. Click 'Create database'"
echo "3. Choose 'Start in production mode'"
echo "4. Select a location close to your users"
echo "5. Click 'Enable'"
echo ""

# Ask if user wants to update firebase.json
read -p "Have you enabled the Firestore API and want to update firebase.json? (y/n): " update_json

if [ "$update_json" = "y" ]; then
  # Update firebase.json to include Firestore rules
  echo "Updating firebase.json to include Firestore rules..."
  cat > firebase.json << 'EOL'
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
EOL

  # Deploy Firestore rules
  echo "Deploying Firestore rules and indexes..."
  firebase deploy --only firestore
fi

echo ""
echo "Deployment completed!"
echo "Please verify that everything works correctly." 