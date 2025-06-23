#!/bin/bash

echo "===== Firebase Deployment Script ====="
echo "This script will help deploy your Firestore database and rules"
echo

echo "Checking if Firebase CLI is installed..."
if ! command -v firebase &> /dev/null; then
  echo "Firebase CLI not found. Installing..."
  npm install -g firebase-tools
else
  echo "Firebase CLI is installed."
fi

echo
echo "Logging in to Firebase..."
firebase login

echo
echo "=== Firebase Project Information ==="
firebase projects:list

echo
echo "Setting up the current project..."
firebase use recipekeeper-d436a

echo
echo "Checking Firestore database status..."
firebase firestore:databases:list

echo
echo "Would you like to create a new Firestore database if needed? (Y/N)"
read create_db
if [[ "$create_db" == "Y" || "$create_db" == "y" ]]; then
  echo "Creating Firestore database in default location (nam5)..."
  firebase firestore:databases:create --location=nam5
fi

echo
echo "Deploying Firestore security rules..."
firebase deploy --only firestore:rules

echo
echo "Generating Firestore indexes..."
firebase deploy --only firestore:indexes

echo
echo "=== Deployment Complete ==="
echo
echo "Next steps:"
echo "1. Make sure your app has at least one authenticated user"
echo "2. Try creating a test recipe once logged in"
echo
echo "Press enter to continue..."
read 