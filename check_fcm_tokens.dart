import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  // Khởi tạo Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
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