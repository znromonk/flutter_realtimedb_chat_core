<h1 align="center">Flutter Firebase Chat Core (Realtime Database)</h1>

<p align="center">
  Flutter Firebase Chat Core using Realtime Database which can be used with an optional <a href="https://pub.dev/packages/flutter_chat_ui">chat UI</a> by the folks at <a href="https://flyer.chat/">Flyer</a>.
</p>

<hr>

> This is not an actively maintained plugin.
> 
> Feel free to fork and publish to pub.dev

The code is heavily based on the Firestore based plugin <a href="https://github.com/flyerhq/flutter_firebase_chat_core">Flutter Firebase Chat Core</a>. Realtime Database's filtering and querying features are limited, the queries are not shallow (Firestore queries are shallow). As a result, a few sections of the code are not as efficient. To overcome the deep queries performed by Realtime Database, messages for rooms are moved to a higher level alongside rooms and users. The Realtime Database structure is as follows:

```
database
    |----- users
            |----- userID
                    |----- user details
    |----- rooms
            |----- roomID
                    |----- room details
    |----- messages
            |----- roomsID
                    |----- messages for roomID
```

## Realtime Databse Rules
Firebase Realtime Database does not have the level of fine-grained access control as Firestore. I have tested it with the follwing rules. These rules are not secure and only use ir for testing.
```
{
  "rules": {
    "users":{
      ".read": "auth !=null",
      ".write": "auth !=null",
      "$user_id":{
        ".read": "auth !=null",
        ".write": "auth !=null",
      }
    },
    "rooms":{
      ".read": "auth !=null",
      ".write": "auth !=null",
      "$room_id":{
        ".read": "auth !=null",
        ".write": "auth !=null",
      }
    },
    "messages":{
      ".read": "auth !=null",
      "$room_id":{
        ".read": "auth !=null",
        ".write": "auth !=null",
      }
    }
  }
}
```
An alternative way to restrict the read/write permissions to only authorized users is to use a form of rule such as:
```
".read": "root.child('rooms').child($room_id).child('userIds').child(auth.uid).val() == true",
```
inside the room_id child. To use this rule, userIds need to change from a List saved as a String to Map such as:
```
userIds:{
  'user1Id': true,
  'user2Id': true,
  }
```


## TODO

* Better filtering of rooms to emulate Firestore queries by creting an index for each room

## Usage

Included is a modified (based on original Flutter Firebase Chat Core plugin) example to get started.
