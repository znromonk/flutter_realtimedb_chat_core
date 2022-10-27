import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import 'realtimedb_chat_core_config.dart';
import 'util.dart';

/// Provides access to Firebase chat data. Singleton, use
/// FirebaseChatCore.instance to aceess methods.
class FirebaseChatCore {
  FirebaseChatCore._privateConstructor() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      firebaseUser = user;
    });
  }

  /// Config to set custom names for rooms and users collections. Also
  /// see [RealtimeDBChatCoreConfig].
  RealtimeDBChatCoreConfig config =
      const RealtimeDBChatCoreConfig(null, 'rooms', 'users', 'messages');

  /// Current logged in user in Firebase. Does not update automatically.
  /// Use [FirebaseAuth.authStateChanges] to listen to the state changes.
  User? firebaseUser = FirebaseAuth.instance.currentUser;

  /// Singleton instance.
  static final FirebaseChatCore instance =
      FirebaseChatCore._privateConstructor();

  /// Gets proper [FirebaseDatabase] instance.
  FirebaseDatabase getFirebaseDatabase() => config.firebaseAppName != null
      ? FirebaseDatabase.instanceFor(
          app: Firebase.app(config.firebaseAppName!),
        )
      : FirebaseDatabase.instance;

  /// Sets custom config to change default names for rooms
  /// and users collections. Also see [RealtimeDBChatCoreConfig].
  void setConfig(RealtimeDBChatCoreConfig RealtimeDBChatCoreConfig) {
    config = RealtimeDBChatCoreConfig;
  }

  /// Creates a chat group room with [users]. Creator is automatically
  /// added to the group. [name] is required and will be used as
  /// a group name. Add an optional [imageUrl] that will be a group avatar
  /// and [metadata] for any additional custom data.
  Future<types.Room> createGroupRoom({
    types.Role creatorRole = types.Role.admin,
    String? imageUrl,
    Map<String, dynamic>? metadata,
    required String name,
    required List<types.User> users,
  }) async {
    if (firebaseUser == null) return Future.error('User does not exist');

    final currentUser = await fetchUser(
      getFirebaseDatabase(),
      firebaseUser!.uid,
      config.usersCollectionName,
      role: creatorRole.toShortString(),
    );

    final roomUsers = [types.User.fromJson(currentUser)] + users;

    final roomID = getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .push()
        .key;

    await getFirebaseDatabase()
        .ref()
        .child('${config.roomsCollectionName}/$roomID')
        .set({
      'createdAt': ServerValue.timestamp,
      'imageUrl': imageUrl,
      'metadata': metadata,
      'name': name,
      'type': types.RoomType.group.toShortString(),
      'updatedAt': ServerValue.timestamp,
      'userIds': roomUsers.map((u) => u.id).toList(),
      'userRoles': roomUsers.fold<Map<String, String?>>(
        {},
        (previousValue, user) => {
          ...previousValue,
          user.id: user.role?.toShortString(),
        },
      ),
    });

    return types.Room(
      id: roomID!,
      imageUrl: imageUrl,
      metadata: metadata,
      name: name,
      type: types.RoomType.group,
      users: roomUsers,
    );
  }

  /// Creates a direct chat for 2 people. Add [metadata] for any additional
  /// custom data.
  Future<types.Room> createRoom(
    types.User otherUser, {
    Map<String, dynamic>? metadata,
  }) async {
    final fu = firebaseUser;

    if (fu == null) return Future.error('User does not exist');

    // Sort two user ids array to always have the same array for both users,
    // this will make it easy to find the room if exist and make one read only.
    final userIds = [fu.uid, otherUser.id]..sort();

    final roomQuery = await getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .orderByChild('typeUserIds')
        .equalTo(
            '${types.RoomType.direct.toShortString()}${jsonEncode(userIds)}')
        .limitToFirst(1)
        .get();

    // Check if room already exist.
    if (roomQuery.value != null) {
      final room = (await processRoomsQuery(
        fu,
        getFirebaseDatabase(),
        roomQuery,
        config.usersCollectionName,
      ))
          .first;

      return room;
    }

    // To support old chats created without sorted array,
    // try to check the room by reversing user ids array.
    final oldRoomQuery = await getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .orderByChild('typeUserIds')
        .equalTo(
            '${types.RoomType.direct.toShortString()}${jsonEncode(userIds.reversed.toList())}')
        .limitToFirst(1)
        .get();

    // Check if room already exist.
    if (oldRoomQuery.value != null) {
      final room = (await processRoomsQuery(
        fu,
        getFirebaseDatabase(),
        oldRoomQuery,
        config.usersCollectionName,
      ))
          .first;

      return room;
    }

    final currentUser = await fetchUser(
      getFirebaseDatabase(),
      fu.uid,
      config.usersCollectionName,
    );

    final users = [types.User.fromJson(currentUser), otherUser];

    final roomID = getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .push()
        .key;

    // Create new room with sorted user ids array.
    await getFirebaseDatabase()
        .ref()
        .child('${config.roomsCollectionName}/$roomID')
        .set({
      'createdAt': ServerValue.timestamp,
      'imageUrl': null,
      'metadata': metadata,
      'name': null,
      'type': types.RoomType.direct.toShortString(),
      'updatedAt': ServerValue.timestamp,
      'userIds': jsonEncode(userIds),
      'userRoles': null,
      'typeUserIds':
          '${types.RoomType.direct.toShortString()}${jsonEncode(userIds)}',
    });

    return types.Room(
      id: roomID!,
      metadata: metadata,
      type: types.RoomType.direct,
      users: users,
    );
  }

  /// Creates [types.User] in Firebase to store name and avatar used on
  /// rooms list
  Future<void> createUserInRealtimeDB(types.User user) async {
    // only create if user does not exist
    if ((await getFirebaseDatabase()
                .ref()
                .child(config.usersCollectionName)
                .child(user.id)
                .get())
            .value ==
        null) {
      await getFirebaseDatabase()
          .ref()
          .child(config.usersCollectionName)
          .child(user.id)
          .set({
        'createdAt': ServerValue.timestamp,
        'firstName': user.firstName,
        'imageUrl': user.imageUrl,
        'lastName': user.lastName,
        'lastSeen': ServerValue.timestamp,
        'metadata': user.metadata,
        'role': user.role?.toShortString(),
        'updatedAt': ServerValue.timestamp,
      });
    }
  }

  /// Removes message document.
  Future<void> deleteMessage(String roomId, String messageId) async {
    await getFirebaseDatabase()
        .ref()
        .child('${config.messagesCollectionName}/$roomId')
        .child(messageId)
        .remove();
  }

  /// Removes all message from a room.
  Future<void> deleteAllMessageFromRoom(String roomId) async {
    await getFirebaseDatabase()
        .ref()
        .child('${config.messagesCollectionName}/$roomId')
        .remove();
  }

  /// Removes room document.
  Future<void> deleteRoom(String roomId) async {
    await getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .child(roomId)
        .remove();

    // remove the messages associated with the room
    await deleteAllMessageFromRoom(roomId);
  }

  /// Removes [types.User] from `users` collection in Firebase.
  Future<void> deleteUserFromRealtimeDB(String userId) async {
    await getFirebaseDatabase()
        .ref()
        .child(config.usersCollectionName)
        .child(userId)
        .remove();
  }

  /// Returns a stream of messages from Firebase for a given room.
  Stream<List<types.Message>> messages(
    types.Room room, {
    List<Object?>? endAt,
    List<Object?>? endBefore,
    int? limit,
    List<Object?>? startAfter,
    List<Object?>? startAt,
  }) {
    var query = getFirebaseDatabase()
        .ref()
        .child('${config.messagesCollectionName}/${room.id}')
        .orderByChild('createdAt');

    if (endAt != null) {
      query = query.endAt(endAt);
    }

    if (endBefore != null) {
      query = query.endBefore(endBefore);
    }

    if (limit != null) {
      query = query.limitToFirst(limit);
    }

    if (startAfter != null) {
      query = query.startAfter(startAfter);
    }

    if (startAt != null) {
      query = query.startAt(startAt);
    }

    return query.onValue.map(
      (dbEvent) {
        Map<Object?, Object?>? snapshotValue =
            dbEvent.snapshot.value as Map<Object?, Object?>?;
        if (snapshotValue == null) {
          return [];
        }
        return (snapshotValue).entries.fold<List<types.Message>>(
          [],
          (previousValue, entry) {
            final data = Map<String, dynamic>.from(entry.value as Map);
            final author = room.users.firstWhere(
              (u) => u.id == data['authorId'],
              orElse: () => types.User(id: data['authorId'] as String),
            );

            data['author'] = author.toJson();
            data['createdAt'] = data['createdAt'];
            data['id'] = entry.key;
            data['updatedAt'] = data['updatedAt'];

            return [...previousValue, types.Message.fromJson(data)];
          },
        )..sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
      },
    );
  }

  /// Returns a stream of changes in a room from Firebase.
  Stream<types.Room> room(String roomId) {
    final fu = firebaseUser;

    if (fu == null) return const Stream.empty();

    return getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .child(roomId)
        .onValue
        .asyncMap(
      (doc) {
        // print('asyncmap: ${doc.snapshot.value}');
        return processRoomDocument(
          (doc.snapshot.value as Map<Object?, Object?>).entries.first,
          fu,
          getFirebaseDatabase(),
          config.usersCollectionName,
        );
      },
    );
  }

  /// Returns a stream of rooms from Firebase. Only rooms where current
  /// logged in user exist are returned. [orderByUpdatedAt] is used in case
  /// you want to have last modified rooms on top, there are a couple
  /// of things you will need to do though:
  /// 1) Make sure `updatedAt` exists on all rooms
  /// 2) Write a Cloud Function which will update `updatedAt` of the room
  /// when the room changes or new messages come in
  /// 3) Create an Index (Firestore Database -> Indexes tab) where collection ID
  /// is `rooms`, field indexed are `userIds` (type Arrays) and `updatedAt`
  /// (type Descending), query scope is `Collection`
  Stream<List<types.Room>> rooms({bool orderByUpdatedAt = false}) {
    final fu = firebaseUser;

    if (fu == null) return const Stream.empty();

    // TODO: Find realtimedb equivalent of the below comment
    // final collection = orderByUpdatedAt
    //     ? getFirebaseDatabase()
    //         .ref()
    //         .child(config.roomsCollectionName)
    //         .where('userIds', arrayContains: fu.uid)
    //         .orderBy('updatedAt', descending: true)
    //     : getFirebaseDatabase()
    //         .ref()
    //         .child(config.roomsCollectionName)
    //         .where('userIds', arrayContains: fu.uid);

    return getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .onValue
        .asyncMap(
          (dbEvent) => processRoomsQuery(
            fu,
            getFirebaseDatabase(),
            dbEvent.snapshot,
            config.usersCollectionName,
          ),
        );
  }

  /// Sends a message to the RealtimeDB. Accepts any partial message and a
  /// room ID. If arbitraty data is provided in the [partialMessage]
  /// does nothing.
  void sendMessage(dynamic partialMessage, String roomId) async {
    if (firebaseUser == null) return;

    types.Message? message;

    if (partialMessage is types.PartialCustom) {
      message = types.CustomMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialCustom: partialMessage,
      );
    } else if (partialMessage is types.PartialFile) {
      message = types.FileMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialFile: partialMessage,
      );
    } else if (partialMessage is types.PartialImage) {
      message = types.ImageMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialImage: partialMessage,
      );
    } else if (partialMessage is types.PartialText) {
      message = types.TextMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialText: partialMessage,
      );
    }

    if (message != null) {
      final messageMap = message.toJson();
      messageMap.removeWhere((key, value) => key == 'author' || key == 'id');
      messageMap['authorId'] = firebaseUser!.uid;
      messageMap['createdAt'] = ServerValue.timestamp;
      messageMap['updatedAt'] = ServerValue.timestamp;

      await getFirebaseDatabase()
          .ref()
          .child('${config.messagesCollectionName}/$roomId')
          .push()
          .set(messageMap);

      await getFirebaseDatabase()
          .ref()
          .child(config.roomsCollectionName)
          .child(roomId)
          .update({'updatedAt': ServerValue.timestamp});
    }
  }

  /// Updates a message in the RealtimeDB. Accepts any message and a
  /// room ID. Message will probably be taken from the [messages] stream.
  void updateMessage(types.Message message, String roomId) async {
    if (firebaseUser == null) return;
    if (message.author.id != firebaseUser!.uid) return;

    final messageMap = message.toJson();
    messageMap.removeWhere(
      (key, value) => key == 'author' || key == 'createdAt' || key == 'id',
    );
    messageMap['authorId'] = message.author.id;
    messageMap['updatedAt'] = ServerValue.timestamp;

    await getFirebaseDatabase()
        .ref()
        .child('${config.messagesCollectionName}/$roomId')
        .child(message.id)
        .update(messageMap);
  }

  /// Updates a room in the RealtimeDB. Accepts any room.
  /// Room will probably be taken from the [rooms] stream.
  void updateRoom(types.Room room) async {
    if (firebaseUser == null) return;

    final roomMap = room.toJson();
    roomMap.removeWhere((key, value) =>
        key == 'createdAt' ||
        key == 'id' ||
        key == 'lastMessages' ||
        key == 'users');

    if (room.type == types.RoomType.direct) {
      roomMap['imageUrl'] = null;
      roomMap['name'] = null;
    }

    roomMap['lastMessages'] = room.lastMessages?.map((m) {
      final messageMap = m.toJson();

      messageMap.removeWhere((key, value) =>
          key == 'author' ||
          key == 'createdAt' ||
          key == 'id' ||
          key == 'updatedAt');

      messageMap['authorId'] = m.author.id;

      return messageMap;
    }).toList();
    roomMap['updatedAt'] = ServerValue.timestamp;
    roomMap['userIds'] = room.users.map((u) => u.id).toList();

    await getFirebaseDatabase()
        .ref()
        .child(config.roomsCollectionName)
        .child(room.id)
        .update(roomMap);
  }

  /// Returns a stream of all users from Firebase.
  Stream<List<types.User>> users() {
    if (firebaseUser == null) return const Stream.empty();
    return getFirebaseDatabase()
        .ref()
        .child(config.usersCollectionName)
        .onValue
        .map<List<types.User>>(
      (dbEvent) {
        return (dbEvent.snapshot.value as Map<Object?, Object?>)
            .entries
            .fold<List<types.User>>(
          [],
          (previousValue, doc) {
            if (firebaseUser!.uid == doc.key) return previousValue;

            final data = Map<String, dynamic>.from(doc.value as Map);

            data['createdAt'] = data['createdAt'];
            data['id'] = doc.key;
            data['lastSeen'] = data['lastSeen'];
            data['updatedAt'] = data['updatedAt'];

            return [...previousValue, types.User.fromJson(data)];
          },
        );
      },
    );
  }
}
