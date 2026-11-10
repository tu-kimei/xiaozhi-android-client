<h1 align="center">AI Robot Buddy for Kids</h1>

<p align="center">
  <b>An AI companion robot and English tutor for young children</b><br>
  <sub>A Flutter app that turns a UBTech Visbot robot into a hands-free, voice-first buddy for kids</sub>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/Apache-2.0"><img src="https://img.shields.io/badge/License-Apache_2.0-green.svg?style=flat-square" alt="License: Apache-2.0"/></a>
  <img src="https://img.shields.io/badge/Flutter-3.7%2B-02569B?style=flat-square&logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Android-8.1%2B-3DDC84?style=flat-square&logo=android" alt="Android"/>
</p>

---

## About

This project builds an AI assistant robot that talks with young children and helps them learn.
The target user is a **5-year-old**: they cannot read menus or hold a push-to-talk button, so
everything works by voice. The child just speaks to the robot. The robot answers out loud, shows a
matching face on its screen, and moves its head and wheels.

The app runs on a **UBTech Visbot** robot (Android 8.1, armeabi-v7a, 308×240 screen). It talks to
a [Xiaozhi](https://github.com/78/xiaozhi-esp32)-compatible server, which handles speech
recognition, the language model and text-to-speech. The default conversation language is
**Vietnamese**.

It is a fork of [TOM88812/xiaozhi-android-client](https://github.com/TOM88812/xiaozhi-android-client),
adapted for a children's robot.

## Goals

- **Companion**: a friendly robot a child can chat with, ask questions, and hear stories from.
- **Tutor**: teach English to young children with a curriculum that parents set up and follow.
- **Safe and simple**: no buttons or menus for the child; parents control the settings.
- **Own the data**: move from the public xiaozhi.me server to a self-hosted server on a VPS.

## Features

| Feature | Status |
|:---|:---:|
| Vietnamese UI and Vietnamese conversation | ✅ |
| Hands-free voice chat (server-side VAD, no push-to-talk) | ✅ |
| Xiaozhi protocol: OTA activation, MQTT + UDP (AES-CTR) and WebSocket | ✅ |
| Smooth audio playback on the robot (native streaming player, jitter buffer, Opus loss concealment) | ✅ |
| Filters out phantom speech that the speech recognizer "hears" in background noise | ✅ |
| Robot control: head tilt, driving and turning, stop | ✅ |
| Emotion face on screen that follows the conversation | 🚧 |
| Voice commands for the robot ("move forward a bit and spin left") over MCP, plus natural gestures while talking | 🚧 |
| Standby mode with a wake word, to save battery | 🚧 |
| English tutor: Tutor Service + parent web UI + lesson flow on the robot | 📝 |
| Self-hosted Xiaozhi server on a VPS | 📝 |

✅ done · 🚧 in progress · 📝 planned

Work in progress lives on the development branches (`vietnamese-and-robot-control`,
`feat/visbot-next-phase`), together with the design plans in `docs/plans/`.

## How it works

```
 Child ──voice──▶  Visbot robot (this app)  ──MQTT/UDP or WS──▶  Xiaozhi server
                     │  mic, speaker, face,                       ASR → LLM → TTS
                     │  head & wheels                                    │
                     │◀──────────── audio reply + emotion + MCP tool calls ┘
                     │
                     └──HTTPS──▶  Tutor Service (planned, on the same VPS)
                                   curriculum, progress, lesson brief
                                   ▲
                       Parents ────┘ web UI
```

- The robot works as a standard Xiaozhi device. Switching servers is only a configuration change
  (the OTA URL in settings).
- The device exposes the robot's abilities (motion, face, tutor lessons) to the server's language
  model as **MCP tools**, so any compatible server can use them.
- The Tutor Service will keep learning progress as structured data, not in the model's memory.
  At the start of each session, the robot fetches a short "lesson brief": the current lesson,
  the words due for review and past mistakes.

## Getting started

Requirements: Flutter 3.7+, JDK 17 and the Android SDK. You also need a Visbot robot, or any
Android 8.1+ device (without the robot features).

```bash
flutter pub get
flutter build apk --debug --target-platform android-arm
```

On the Visbot, install with the chunked installer `scripts/install_chunked.sh` (on the
development branches) instead of `adb install`. The USB link (usbip on WSL2) drops large
transfers. Then open **Settings**, enter the server's OTA URL, and activate the device with the
code it shows.

## Roadmap

1. Voice control of the robot and natural gestures (MCP on the device).
2. Emotion face driven by the conversation.
3. English tutor: a separate Tutor Service with a web UI for parents to build the curriculum,
   pick lessons and follow progress, with spaced-repetition review and resumable lessons.
4. Self-hosted Xiaozhi server and Tutor Service on one VPS.

## Credits

- [TOM88812/xiaozhi-android-client](https://github.com/TOM88812/xiaozhi-android-client): the
  original cross-platform Xiaozhi client this project is based on.
- [78/xiaozhi-esp32](https://github.com/78/xiaozhi-esp32): the Xiaozhi device protocol.

## License

[Apache License 2.0](LICENSE). UBTech's own robot resources (emotion animations, dances, sounds)
are read on the device only and are not included in this repository.
