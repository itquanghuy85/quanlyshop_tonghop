import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  await Firebase.initializeApp();

  final shopId = 'honC8KnKhOUG19wcYOFDTGVdKWP2';

  try {
    final userDocs = await FirebaseFirestore.instance
        .collection('users')
        .where('shopId', '==', shopId)
        .get();

    print('Found ${userDocs.docs.length} users in shop $shopId:');

    for (final doc in userDocs.docs) {
      final userData = doc.data();
      final userId = doc.id;
      final fcmToken = userData['fcmToken'];
      final email = userData['email'];

      print('User: $userId ($email)');
      print('  FCM Token: ${fcmToken != null ? fcmToken.substring(0, 50) + "..." : "NULL"}');
      print('  Token length: ${fcmToken?.length ?? 0}');
      print('');
    }
  } catch (e) {
    print('Error: $e');
  }
}