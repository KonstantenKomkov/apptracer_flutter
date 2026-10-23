## 0.1.0-dev.1

- Add an experimental official Sentry SDK adapter with explicit ownership,
  filtered event mapping and fail-safe initialization.
- Add macOS Cocoa lifecycle ownership, cancellable delivery, durable replay
  revocation and isolated queue cleanup; restarting after native init requires a
  new process. Keep Windows purge and full live platform acceptance open.
