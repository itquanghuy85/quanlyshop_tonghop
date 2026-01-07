const admin = require('firebase-admin');

// Khởi tạo Firebase Admin SDK
admin.initializeApp();

async function checkFCMTokens() {
  const db = admin.firestore();

  // Query collection 'users' với shopId
  const querySnapshot = await db.collection('users')
    .where('shopId', '==', 'honC8KnKhOUG19wcYOFDTGVdKWP2')
    .get();

  // In ra fcmToken của mỗi user
  querySnapshot.forEach((doc) => {
    const data = doc.data();
    const fcmToken = data.fcmToken;
    const userId = doc.id;
    console.log(`User ID: ${userId}, FCM Token: ${fcmToken}`);
  });
}

checkFCMTokens().catch(console.error);