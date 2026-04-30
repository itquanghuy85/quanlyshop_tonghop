import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'storage_service.dart';
import 'user_service.dart';

class CommunityService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _postsRef =>
      _db.collection('community_posts');

  static CollectionReference<Map<String, dynamic>> _commentsRef(String postId) =>
      _postsRef.doc(postId).collection('comments');

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPosts({
    required String shopId,
    int limit = 40,
  }) {
    // Keep this query index-free (shopId equality only), then filter/sort in UI.
    // This avoids FAILED_PRECONDITION composite-index errors on community feed.
    return _postsRef
        .where('shopId', isEqualTo: shopId)
        .limit(limit * 5)
        .snapshots();
  }

  static Future<bool> createPost({
    required String shopId,
    required String content,
    File? imageFile,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final trimmed = content.trim();
      if (trimmed.isEmpty && imageFile == null) {
        NotificationService.showSnackBar(
          'Bài viết cần có nội dung hoặc hình ảnh',
          color: const Color(0xFFE67E22),
        );
        return false;
      }

      String imageUrl = '';
      if (imageFile != null) {
        final uploaded = await StorageService.uploadAndGetUrl(
          imageFile.path,
          'chat_images/$shopId',
        );
        if (uploaded == null || uploaded.trim().isEmpty) {
          NotificationService.showSnackBar(
            'Không thể tải ảnh bài viết',
            color: const Color(0xFFE74C3C),
          );
          return false;
        }
        imageUrl = uploaded;
      }

      final userInfo = await UserService.getUserInfo(currentUser.uid);
      final displayName =
          (userInfo['displayName'] ?? userInfo['name'] ?? '').toString().trim();
      final role = (userInfo['role'] ?? 'employee').toString();
      final photoUrl = (userInfo['photoUrl'] ?? '').toString().trim();

      await _postsRef.add({
        'shopId': shopId,
        'authorUid': currentUser.uid,
        'authorName': displayName.isEmpty
            ? (currentUser.email ?? 'Nhân viên')
            : displayName,
        'authorRole': role,
        'authorPhotoUrl': photoUrl,
        'content': trimmed,
        'imageUrl': imageUrl,
        'likedBy': <String>[],
        'likeCount': 0,
        'commentCount': 0,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi đăng bài: $e',
        color: const Color(0xFFE74C3C),
      );
      return false;
    }
  }

  static Future<void> toggleLike({
    required String postId,
    required bool isLiked,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docRef = _postsRef.doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final likedBy = List<String>.from((data['likedBy'] as List?) ?? const []);
      final hasLike = likedBy.contains(uid);

      if (isLiked && hasLike) {
        likedBy.remove(uid);
      } else if (!isLiked && !hasLike) {
        likedBy.add(uid);
      }

      tx.set(docRef, {
        'likedBy': likedBy,
        'likeCount': likedBy.length,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamComments(
    String postId,
  ) {
    return _commentsRef(postId)
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();
  }

  static Future<bool> addComment({
    required String postId,
    required String content,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;
      final trimmed = content.trim();
      if (trimmed.isEmpty) return false;

      final userInfo = await UserService.getUserInfo(currentUser.uid);
      final displayName =
          (userInfo['displayName'] ?? userInfo['name'] ?? '').toString().trim();
      final role = (userInfo['role'] ?? 'employee').toString();
      final photoUrl = (userInfo['photoUrl'] ?? '').toString().trim();

      await _commentsRef(postId).add({
        'authorUid': currentUser.uid,
        'authorName': displayName.isEmpty
            ? (currentUser.email ?? 'Nhân viên')
            : displayName,
        'authorRole': role,
        'authorPhotoUrl': photoUrl,
        'content': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _postsRef.doc(postId).set({
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      NotificationService.showSnackBar(
        'Không thể gửi bình luận: $e',
        color: const Color(0xFFE74C3C),
      );
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }
}
