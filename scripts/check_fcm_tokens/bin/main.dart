import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // Khởi tạo Firebase - sử dụng env vars hoặc firebase_options
  // Chạy: dart run --define=API_KEY=xxx --define=APP_ID=xxx
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: const String.fromEnvironment('API_KEY'),
      appId: const String.fromEnvironment('APP_ID'),
      messagingSenderId: const String.fromEnvironment('SENDER_ID'),
      projectId: const String.fromEnvironment('PROJECT_ID'),
      storageBucket: const String.fromEnvironment('STORAGE_BUCKET'),
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