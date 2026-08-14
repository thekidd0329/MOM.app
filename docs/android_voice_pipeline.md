# MOM Android on-device voice pipeline

This is the privacy boundary for MOM's Android voice path. Speech audio stays
on the phone. Supabase receives text or bounded structured data only.

## Hard invariants

- Android microphone buffers never cross the Flutter method channel.
- Recognition uses `SpeechRecognizer.createOnDeviceSpeechRecognizer` only.
- The generic `createSpeechRecognizer` factory is forbidden because its
  implementation may use a remote service.
- There is no network recognition fallback. If an on-device recognizer or
  language model is unavailable, voice fails closed and keyboard input remains
  available.
- Raw conversation turns remain in the local conversation store.
- Cloud event telemetry is content-free and rejects transcript and audio fields.

## Runtime flow

1. The Android activity starts the API 31+ on-device recognizer after checking
   the microphone permission and local-recognizer availability.
2. Android emits partial/final text, status, confidence, and errors to Flutter.
   `onBufferReceived` is deliberately discarded.
3. Flutter performs transcript quality checks, redirect/barge-in decisions, and
   privacy filtering locally.
4. The raw user turn is appended to the local conversation store.
5. Text follows explicit, separate Supabase routes:

| Route | Input | Persistence contract |
| --- | --- | --- |
| `mom-brain-stream` | Current text plus bounded text history | Used transiently for inference; this function does not write chat text to Postgres. |
| `mom-intelligence` | Locally de-identified text | Persists detached structured facts and temporal items; rejects raw text and audio fields. |
| `mom-sync` | Content-free operational events | Persists bounded telemetry; rejects transcript, prompt, message, and audio fields. |

The app labels inference requests with `input_transport: text` and
`audio_uploaded: false`. Edge Functions reject audio-bearing request fields so
an accidental client regression fails at the server boundary too.

## Availability and lifecycle

- Minimum strict path: Android 12 (API 31) with an installed on-device speech
  recognition service and downloaded language model.
- The recognition listener is installed before `startListening`.
- Generation IDs suppress callbacks from cancelled sessions.
- Conversation changes use cancellation so a stale final result cannot leak
  into the next turn.
- The recognizer is destroyed with the Activity/Flutter service lifecycle.
- The UI says `Listening...` only after the local recognition session starts;
  the idle state says `Ready`.
- Kokoro voice assets are loaded lazily when speech output is first requested;
  app startup no longer performs a background model download.

## Future app-owned model fallback

An app-bundled CrispASR recognizer can implement `MomSpeechRecognizer` later
for devices without Android's installed on-device service. It must consume PCM
in memory, use a verified local model, expose the same text-only interface, and
must never fall back to a network recognizer.
