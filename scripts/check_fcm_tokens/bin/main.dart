import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // Khởi tạo Firebase với options hardcoded
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyA5wW6zMHiWB_5xme99MVl0eSj7bhpO-S0',
      appId: '1:51200928212:android:c0d1e9d964b3213b910e41',
      messagingSenderId: '51200928212',
      projectId: 'huyaka-1809',
      storageBucket: 'huyaka-1809.firebasestorage.app',
    ),
  );

  // Query Firestore collection 'users' với shopId
  final querySnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('shopId', isEqualTo: 'honC8KnKhOUG19wcYOFDTGVdKWP2')
      .get();

  // In ra fcmToken của mỗi user
  for (var doc in querySnapshot.docs) {
    final data = doc.data();
    final fcmToken = data['fcmToken'];
    final userId = doc.id;
    print('User ID: $userId, FCM Token: $fcmToken');
  }
}