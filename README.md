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

## TODO

* Better filtering of rooms to emulate Firestore queries by creting an index for each room

## Usage

Included is a modified (based on original Flutter Firebase Chat Core plugin) example to get started.
