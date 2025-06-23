/**
 * Firebase/Firestore Database Check Script
 * 
 * This script connects to your Firebase project and checks if:
 * 1. The Firestore database exists
 * 2. The database is accessible with the provided credentials
 * 3. Security rules are properly configured
 * 
 * Run this script with: node firebase_check.js
 */

// Load environment variables if needed
// require('dotenv').config();

const { initializeApp } = require('firebase/app');
const { getFirestore, collection, getDocs, addDoc, deleteDoc, doc } = require('firebase/firestore');

// Your Firebase configuration from the Firebase console
// This should match your app's configuration
const firebaseConfig = {
  apiKey: "AIzaSyDUayJmryFpuzRbiY_W_1D3bx2wkzNRn2Y",
  projectId: "recipekeeper-d436a",
  authDomain: "recipekeeper-d436a.firebaseapp.com",
  storageBucket: "recipekeeper-d436a.firebasestorage.app",
  messagingSenderId: "682017024777",
  appId: "1:682017024777:web:b53ab4e1120a5e2f8601d8", 
  measurementId: "G-7XZD3KWERF"
};

async function checkFirebaseSetup() {
  try {
    console.log('Starting Firebase connection check...');
    console.log(`Project ID: ${firebaseConfig.projectId}`);
    
    // Initialize Firebase
    const app = initializeApp(firebaseConfig);
    console.log('Firebase initialized successfully');
    
    // Initialize Firestore
    const db = getFirestore(app);
    console.log('Firestore initialized successfully');
    
    // Test health check collection (should be publicly accessible)
    try {
      console.log('Testing health_check collection (public access)...');
      const healthCheckDoc = await addDoc(collection(db, '_health_check'), {
        timestamp: new Date().toISOString(),
        message: 'Connection test from Node.js script'
      });
      console.log('Successfully wrote to _health_check collection');
      
      // Clean up test document
      await deleteDoc(healthCheckDoc);
      console.log('Successfully deleted test document');
    } catch (error) {
      console.error('Error testing health_check collection:', error);
      console.log('This indicates either the Firestore database doesn\'t exist or the security rules are too restrictive');
    }
    
    // Try to read from recipes collection
    try {
      console.log('Testing recipes collection...');
      const recipesSnapshot = await getDocs(collection(db, 'recipes'));
      console.log(`Found ${recipesSnapshot.size} recipes`);
    } catch (error) {
      console.error('Error reading recipes collection:', error);
      console.log('This is expected if you\'re not authenticated or if the collection doesn\'t exist yet');
    }
    
    console.log('\nFIREBASE CONNECTION CHECK COMPLETED');
    
    // Provide recommendations
    console.log('\nRecommendations:');
    console.log('1. If you saw "Firestore initialized successfully" but couldn\'t write to _health_check collection:');
    console.log('   - Make sure you\'ve created a Firestore database in the Firebase console');
    console.log('   - Check your security rules to ensure _health_check collection allows public access');
    console.log('2. If you couldn\'t read from recipes collection but _health_check worked:');
    console.log('   - This is expected if you have security rules requiring authentication');
    console.log('   - Create a user account and test with authentication in the app');
    
  } catch (error) {
    console.error('Fatal error:', error);
    console.log('\nPOSSIBLE CAUSES:');
    console.log('1. Incorrect Firebase configuration');
    console.log('2. Firebase project does not exist or was deleted');
    console.log('3. Network connectivity issues');
  }
}

// Run the check
checkFirebaseSetup().catch(console.error); 