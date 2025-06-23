@echo off
echo Building Flutter web app...
call flutter build web

echo Deploying to Firebase hosting...
call firebase deploy --only hosting

echo.
echo IMPORTANT: Before deploying Firestore rules, you need to enable the Firestore API:
echo 1. Go to: https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=recipekeeper-d436a
echo 2. Click the 'Enable' button
echo 3. Wait a few minutes for the API to be enabled
echo.
echo If you haven't created a Firestore database yet:
echo 1. Go to: https://console.firebase.google.com/project/recipekeeper-d436a/firestore
echo 2. Click 'Create database'
echo 3. Choose 'Start in production mode'
echo 4. Select a location close to your users
echo 5. Click 'Enable'
echo.

set /p update_json=Have you enabled the Firestore API and want to update firebase.json? (y/n): 

if "%update_json%"=="y" (
  echo Updating firebase.json to include Firestore rules...
  
  echo {> firebase.json
  echo   "hosting": {>> firebase.json
  echo     "public": "build/web",>> firebase.json
  echo     "ignore": [>> firebase.json
  echo       "firebase.json",>> firebase.json
  echo       "**/.*",>> firebase.json
  echo       "**/node_modules/**">> firebase.json
  echo     ],>> firebase.json
  echo     "rewrites": [>> firebase.json
  echo       {>> firebase.json
  echo         "source": "**",>> firebase.json
  echo         "destination": "/index.html">> firebase.json
  echo       }>> firebase.json
  echo     ]>> firebase.json
  echo   },>> firebase.json
  echo   "firestore": {>> firebase.json
  echo     "rules": "firestore.rules",>> firebase.json
  echo     "indexes": "firestore.indexes.json">> firebase.json
  echo   },>> firebase.json
  echo   "flutter": {>> firebase.json
  echo     "platforms": {>> firebase.json
  echo       "android": {>> firebase.json
  echo         "default": {>> firebase.json
  echo           "projectId": "recipekeeper-d436a",>> firebase.json
  echo           "appId": "1:682017024777:android:60351fed0ebb4eab8601d8",>> firebase.json
  echo           "fileOutput": "android/app/google-services.json">> firebase.json
  echo         }>> firebase.json
  echo       },>> firebase.json
  echo       "dart": {>> firebase.json
  echo         "lib/firebase_options.dart": {>> firebase.json
  echo           "projectId": "recipekeeper-d436a",>> firebase.json
  echo           "configurations": {>> firebase.json
  echo             "android": "1:682017024777:android:60351fed0ebb4eab8601d8",>> firebase.json
  echo             "ios": "1:682017024777:ios:c48cb71f25c5d4608601d8",>> firebase.json
  echo             "macos": "1:682017024777:ios:c48cb71f25c5d4608601d8",>> firebase.json
  echo             "web": "1:682017024777:web:b53ab4e1120a5e2f8601d8",>> firebase.json
  echo             "windows": "1:682017024777:web:e0dfe13f7c1c26368601d8">> firebase.json
  echo           }>> firebase.json
  echo         }>> firebase.json
  echo       }>> firebase.json
  echo     }>> firebase.json
  echo   }>> firebase.json
  echo }>> firebase.json
  
  echo Deploying Firestore rules and indexes...
  call firebase deploy --only firestore
)

echo.
echo Deployment completed!
echo Please verify that everything works correctly.
pause 