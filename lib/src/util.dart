import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

/// Extension with one [toShortString] method.
extension RoleToShortString on types.Role {
  /// Converts enum to the string equal to enum's name.
  String toShortString() => toString().split('.').last;
}

/// Extension with one [toShortString] method.
extension RoomTypeToShortString on types.RoomType {
  /// Converts enum to the string equal to enum's name.
  String toShortString() => toString().split('.').last;
}

/// Fetches user from Firebase and returns a promise.
Future<Map<String, dynamic>> fetchUser(
  FirebaseDatabase instance,
  String userId,
  String usersCollectionName, {
  String? role,
}) async {
  final doc =
      await instance.ref().child(usersCollectionName).child(userId).get();

  final data = Map<String, dynamic>.from(doc.value as Map);
  // print('$userId: $data');

  data['createdAt'] = data['createdAt'];
  data['id'] = userId;
  data['lastSeen'] = data['lastSeen'];
  data['role'] = role;
  data['updatedAt'] = data['updatedAt'];

  return data;
}

/// Returns a list of [types.Room] created from Firebase query.
/// If room has 2 participants, sets correct room name and image.
Future<List<types.Room>> processRoomsQuery(
  User firebaseUser,
  FirebaseDatabase instance,
  DataSnapshot snapshot,
  String usersCollectionName,
) async {
  final futures = (snapshot.value as Map<Object?, Object?>).entries.map(
        (mapEntry) => processRoomDocument(
          mapEntry,
          firebaseUser,
          instance,
          usersCollectionName,
        ),
      );

  return await Future.wait(futures);
}

/// Returns a [types.Room] created from Firebase document.
Future<types.Room> processRoomDocument(
  MapEntry<Object?, Object?> mapEntry,
  User firebaseUser,
  FirebaseDatabase instance,
  String usersCollectionName,
) async {
  final data = Map<String, dynamic>.from(mapEntry.value! as Map);

  data['createdAt'] = data['createdAt'] as int?;
  data['id'] = mapEntry.key as String;
  data['updatedAt'] = data['updatedAt'] as int?;

  var imageUrl = data['imageUrl'] as String?;
  var name = data['name'] as String?;
  final type = data['type'] as String;
  final userIds = List<String>.from(jsonDecode(data['userIds'] as String));
  final userRoles = data['userRoles'] as Map<String, dynamic>?;

  // print('userIds: $userIds');

  final users = await Future.wait(
    userIds.map(
      (userId) => fetchUser(
        instance,
        userId,
        usersCollectionName,
        role: userRoles?[userId] as String?,
      ),
    ),
  );

  if (type == types.RoomType.direct.toShortString()) {
    try {
      final otherUser = users.firstWhere(
        (u) => u['id'] != firebaseUser.uid,
      );

      imageUrl = otherUser['imageUrl'] as String?;
      name = '${otherUser['firstName'] ?? ''} ${otherUser['lastName'] ?? ''}'
          .trim();
    } catch (e) {
      // Do nothing if other user is not found, because he should be found.
      // Consider falling back to some default values.
    }
  }

  data['imageUrl'] = imageUrl;
  data['name'] = name;
  data['users'] = users;

  if (data['lastMessages'] != null) {
    final lastMessages = data['lastMessages'].map((lm) {
      final author = users.firstWhere(
        (u) => u['id'] == lm['authorId'],
        orElse: () => {'id': lm['authorId'] as String},
      );

      lm['author'] = author;
      lm['createdAt'] = lm['createdAt'];
      lm['id'] = lm['id'] ?? '';
      lm['updatedAt'] = lm['updatedAt'];

      return lm;
    }).toList();

    data['lastMessages'] = lastMessages;
  }

  return types.Room.fromJson(data);
}
