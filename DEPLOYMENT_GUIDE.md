# Recipe Keeper App Deployment Guide

This guide will help you deploy your Recipe Keeper app to Firebase Hosting.

## Prerequisites

1. Install Node.js from https://nodejs.org/ (LTS version recommended)
2. Install Firebase CLI by running: `npm install -g firebase-tools`

## Deployment Steps

1. **Login to Firebase**
   ```
   firebase login
   ```

2. **Update Firebase Project ID**
   Open `.firebaserc` file and replace `YOUR_FIREBASE_PROJECT_ID` with your actual Firebase project ID.

3. **Deploy to Firebase**
   ```
   firebase deploy --only hosting
   ```

4. **Verify Deployment**
   After successful deployment, Firebase will provide a hosting URL where your app is live.

## Troubleshooting

- If you encounter any issues with Firebase authentication, try running `firebase logout` and then `firebase login` again.
- Make sure your Firebase project has Hosting enabled in the Firebase Console.
- If you make changes to your app, run `flutter build web` again before deploying.

## Additional Resources

- [Firebase Hosting Documentation](https://firebase.google.com/docs/hosting)
- [Flutter Web Deployment Guide](https://flutter.dev/docs/deployment/web) 