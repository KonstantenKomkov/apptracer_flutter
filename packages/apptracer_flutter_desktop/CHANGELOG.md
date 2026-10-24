## 0.1.0-dev.1

- Add Ubuntu/Linux registration, GTK runner, official persistent Dart/native
  queue, consent revocation, owned uploader cancellation, release/symbol tooling
  and Ubuntu CI.
  Ubuntu 22.04.5 x64 VM acceptance covers Dart/native delivery, source frames,
  grouping and lifecycle; see the Linux preparation record for service UI limits.
  Use the official native backend with `sentry-crash` to deliver native stacks
  and minidump attachments through `/envelope/`; Tracer rejects the Crashpad
  `/minidump/` route. Resolve native source frames in the crash daemon from
  bundled exact-build Breakpad maps before SDK serialization; preserve the
  original frames if maps are missing or their module IDs differ.
  Resolve Dart AOT frames before SDK serialization using optional compact maps,
  with matching stack/loaded ELF/map build IDs and a consent recheck after IO.
  The example includes these maps by default; opt out with
  `TRACER_BUNDLE_DART_SYMBOLS=0` to retain obfuscation. Full DWARF remains private.
  Server processing is separate from this client-side symbolication.
  Collect Linux distro/kernel and hardware model/architecture after consent,
  for both Dart and native events, without hostname or machine identifiers.
  Preserve the FlutterError type name under Dart AOT obfuscation. Verify
  grouping fingerprints and account isolation in the release acceptance driver.

- Verify an isolated macOS release consumer with hosted facade/interface
  dependencies and automatic adapter registration. Add package exclusions and
  migration/privacy guidance; retain the exact SDK pin and unpublished status.

- Prepare Windows x64 registration, runner, native crash probe, PDB retention and
  loopback CI. Refuse default Windows startup until previous-report cleanup is
  implemented. Native lifecycle and live platform acceptance remain open.
- Add an experimental official Sentry SDK adapter with explicit ownership,
  filtered event mapping and fail-safe initialization.
- Add macOS Cocoa lifecycle ownership, cancellable delivery, durable replay
  revocation and isolated queue cleanup; restarting after native init requires a
  new process. Keep Windows purge and full live platform acceptance open.
