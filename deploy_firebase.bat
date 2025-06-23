@echo off
echo ===== Firebase Deployment Script =====
echo This script will help deploy your Firestore database and rules

echo.
echo Checking if Firebase CLI is installed...
call firebase --version > nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo Firebase CLI not found. Installing...
  call npm install -g firebase-tools
) else (
  echo Firebase CLI is installed.
)

echo.
echo Logging in to Firebase...
call firebase login

echo.
echo === Firebase Project Information ===
call firebase projects:list

echo.
echo Setting up the current project...
call firebase use recipekeeper-d436a

echo.
echo Checking Firestore database status...
call firebase firestore:databases:list

echo.
echo Would you like to create a new Firestore database if needed? (Y/N)
set /p create_db=
if /i "%create_db%"=="Y" (
  echo Creating Firestore database in default location (nam5)...
  call firebase firestore:databases:create --location=nam5
)

echo.
echo Deploying Firestore security rules...
call firebase deploy --only firestore:rules

echo.
echo Generating Firestore indexes...
call firebase deploy --only firestore:indexes

echo.
echo === Deployment Complete ===
echo.
echo Next steps:
echo 1. Make sure your app has at least one authenticated user
echo 2. Try creating a test recipe once logged in
echo.
echo Press any key to continue...
pause > nul 