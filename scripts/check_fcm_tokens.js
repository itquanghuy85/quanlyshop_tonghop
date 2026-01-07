const admin = require("firebase-admin");

admin.initializeApp();

async function checkFCMTokens() {
  const shopId = 'honC8KnKhOUG19wcYOFDTGVdKWP2';

  try {
    const userDocs = await admin.firestore()
      .collection('users')
      .where('shopId', '==', shopId)
      .get();

    console.log(`Found ${userDocs.docs.length} users in shop ${shopId}:`);

    userDocs.forEach(doc => {
      const userData = doc.data();
      const userId = doc.id;
      const fcmToken = userData.fcmToken;
      const email = userData.email;

      console.log(`User: ${userId} (${email})`);
      console.log(`  FCM Token: ${fcmToken ? fcmToken.substring(0, 50) + "..." : "NULL"}`);
      console.log(`  Token length: ${fcmToken ? fcmToken.length : 0}`);
      console.log('');
    });
  } catch (error) {
    console.error('Error:', error);
  } finally {
    admin.app().delete();
  }
}

checkFCMTokens();