# Symbolication

What happens to a Dart stack trace in a release build, what Tracer can and
cannot do about it, and what to do so you are not left holding an undecodable
crash six months from now.

Last updated: 2026-08-25.

## The problem

Build with `--obfuscate --split-debug-info` and Dart stack traces stop being
text:

```
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 12345, tid: 12371, name io.flutter.ui
os: android arch: arm64 comp: no sim: no
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
isolate_dso_base: 7938750000, vm_dso_base: 7938750000
    #00 abs 0000007938a1c2f0 virt 00000000002cc2f0
    #01 abs 0000007938a1b114 virt 00000000002cb114
```

Only one thing decodes this: the `app.<platform>-<arch>.symbols` file that the
same build wrote into the `--split-debug-info` directory, fed to
`flutter symbolize`. Lose that file and the trace is lost with it — permanently,
for every user who ever hits that crash.

## What this package guarantees

* The **verbatim** trace, header lines included, is sent as a log entry attached
  to the event (`TracerOptions.attachRawStackTraceAsLog`, on by default). The
  parser never rewrites it: reformatting would destroy the exact bytes
  `flutter symbolize` needs. One deliberate exception, added 2026-08-26: in a
  **readable** trace the frame numbers are rewritten from `#0` to `[0]`,
  because Tracer's console scans the log for the next record marker in sequence
  and chokes on a trace that carries frame numbers of its own (`Match line
  error, expected format: #0 timestamp | text`). An obfuscated trace is left
  byte for byte alone: it is the one that must survive verbatim, and its frames
  are numbered `#00`, `#01`, which the console does not mistake for records.
* `dart.obfuscated` and `dart.build_id` are set as custom keys, so you can tell
  at a glance which symbol file a given event needs.
* Parsed frames keep the virtual address in `virtAddress`, which is the value
  `flutter symbolize` resolves.

What it cannot do is upload the symbol file for you. Read on.

## Two rules that decide whether any of this works

Both come from Tracer's own "Символизация и группировка сбоев" page, and both
are unforgiving.

**1. Mappings apply only to events received after they were uploaded, and there
is no forced re-symbolication.** Upload late and every crash already collected
stays unreadable — permanently. There is no button to fix it afterwards. This
is why the upload scripts here fail closed rather than warn: a release that
shipped without usable symbols cannot be repaired, only re-released.

**2. `crashId` is computed *after* mappings are applied.** The same failure
arriving symbolicated and unsymbolicated therefore lands in two different
groups. A build whose symbols went missing does not merely look bad — it
splits its issues away from every other build's.

### What that means for obfuscated Dart on Android

An obfuscated Dart trace has no names, only addresses, and those move with
every build. Frames forwarded to Tracer end up as
`dart.obfuscated._kDartIsolateSnapshotInstructions+0x...`, so grouping is
**stable within a build and unstable across builds**: the same logical error
opens a new group in every release.

That is inherent to obfuscation rather than a defect here — there is nothing
stable left to group by — but it is worth knowing before choosing it. Two ways
out:

* Build with `--split-debug-info` but **without** `--obfuscate`. Traces keep
  their function names, grouping is stable across releases, and no symbol file
  is needed to read them. For most applications this is the better trade, and
  it is the same recommendation as in "Not obfuscating" below, now with a
  second reason.
* Pass an explicit `issueKey` to `Tracer.recordError` at call sites you care
  about. That pins grouping regardless of what the stack looks like.

## Tracer's symbol channels

Tracer documents three, and none of them is for Dart:

| Artefact | Channel |
|---|---|
| Android `mapping.txt` (R8) | `ru.ok.tracer` Gradle plugin, `uploadMapping` |
| Android native `.so` debug info | same plugin, `uploadNativeSymbols` / `additionalLibrariesPath` |
| iOS `dSYM` | Tracer's Fastlane plugin or its bash script |
| Web source maps | `POST https://plugin-api.apptracer.ru/api/sourcemap/upload` with `sourcemapToken` and `versionName` |

**There is no documented channel for Dart `--split-debug-info` files.** That is
the central fact of this document, and it is why decoding an obfuscated Dart
trace is currently a manual step.

## Findings

### 1. The Dart symbol file and `libapp.so` share a GNU build id — confirmed

Built the example with:

```sh
flutter clean
flutter build apk --release --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/symbols
```

and compared the GNU build-id note of `lib/arm64-v8a/libapp.so` inside the APK
with that of `build/symbols/app.android-arm64.symbols`:

```
libapp.so                 build id: dbcf9df94217e8627e98f3eecfd3d7d7
app.android-arm64.symbols build id: dbcf9df94217e8627e98f3eecfd3d7d7
```

Identical. That is what makes `flutter symbolize` work — and, as the next
finding shows, rather more than that.

### 2. Tracer's own `dump_syms` reads the Dart symbol file — confirmed

This is the useful one.

The `ru.ok.tracer` Gradle plugin ships breakpad `dump_syms` binaries for macOS,
Linux and Windows inside `tracer-plugin-1.4.0.jar`. Its
`ru.ok.tracer.nativesym.CollectSymbolsTask` walks every file under
`build/intermediates/merged_native_libs` — plus anything under
`additionalLibrariesPath`, whose symbols the vendor documents as *overriding*
the ones collected from the merged libs — runs `dump_syms` over each, and
uploads the resulting `.sym`. Verified in the bytecode: it uses `Files.walk`
and filters on being a file, **not** on extension.

Running that exact binary over both files gives:

| Input | Result |
|---|---|
| `app.android-arm64.symbols` | `MODULE Linux arm64 F99DCFDB174262E87E98F3EECFD3D7D70 app.android-arm64.symbols`, 36 324 lines, **7 545 `FUNC` entries** with real Dart names |
| stripped `libapp.so` from the APK | `MODULE Linux arm64 F99DCFDB174262E87E98F3EECFD3D7D70 libapp.so`, 6 lines, **0 `FUNC` entries** |

Same module id — it is derived from the GNU build id, and `INFO CODE_ID`
carries the build id verbatim in both. The Dart symbol file resolves right down
to application code:

```
FUNC 151fb8 8a4 0 _HomePageState.build
FUNC 153094 70  0 _HomePageState._report
FUNC 1543e4 88  0 _HomePageState.build.<anonymous closure>
FILE 201 .../example/lib/main.dart
```

That this is the *intended* use of `additionalLibrariesPath`, rather than an
accident, comes from the plugin itself. One of its own warning messages reads:

> If you're using **additionalLibrariesPath to provide symbol overrides for
> libraries packaged into your application**, you can suppress "Multiple
> different copies..." warnings with `dontWarnAboutLibraryConflicts = true`

`libapp.so` is a library packaged into the application, and better symbols for
it are exactly a symbol override.

The plugin also grades what it parses. `ParsedSymbolFile.Quality` has three
values — `BROKEN`, `CFI_ONLY`, `FULL` — and libraries without usable symbols are
skipped with "No usable symbols found for the following libraries, stacktraces
will be incomplete". The measurements above map straight onto that: the stripped
`libapp.so`, with only `PUBLIC` and `STACK CFI` records, is `CFI_ONLY`; the Dart
symbol file, with 7 545 `FUNC` entries and line tables, is `FULL`.

So the vendor's existing native-symbol channel can carry Dart AOT symbols. Two
details have to be handled first.

**The module name.** `dump_syms` takes the `MODULE` name from the file name, so
as shipped the upload would be called `app.android-arm64.symbols` rather than
`libapp.so`. Copying the file to `libapp.so` in a staging directory makes both
the name and the build id match — confirmed by re-running `dump_syms` on the
renamed copy. `ParsedSymbolFile` exposes `moduleName`, `buildId` and
`isProperBuildId`, so both are read and checked.

**The existence check.** Before uploading, the plugin asks the API whether
symbols for the build already exist (`nativesymbol/exists`) and skips the upload
if they do — and an ordinary build will already have uploaded the stripped
`libapp.so`. `forceUploadNativeSymbols = true` is therefore **required**, not
optional; without it the Dart symbols are silently never sent and the experiment
measures nothing. The plugin says as much when forced: "Uploading them anyway
due to forced upload".

`tool/prepare_dart_symbols.sh` does that, keyed by build id so a multi-ABI build
does not collide:

```sh
flutter build apk --release --obfuscate --split-debug-info=build/symbols
tool/prepare_dart_symbols.sh build/symbols
# -> build/symbols/tracer-upload/<build-id>/libapp.so
```

then point the Gradle plugin at it:

```groovy
tracer {
    create('defaultConfig') {
        additionalLibrariesPath = "$projectDir/../build/symbols/tracer-upload/<build-id>"
    }
}
```

The example wires this up behind an environment variable:

```sh
DART_SPLIT_DEBUG_INFO=$PWD/build/symbols/tracer-upload/<build-id> \
flutter build apk --release -Ptracer.enabled=true \
  --obfuscate --split-debug-info=build/symbols
```

The example's `tracer.gradle` sets `forceUploadNativeSymbols = true` whenever
that variable is present, for the reason given above.

**Upload confirmed 2026-08-26.** Against a live project the plugin logged
`Uploading libapp.so:<build-id>` for all three staged architectures, with ids
matching the staged files, and the build succeeded. The same run printed
`Uploading them anyway due to forced upload`, which confirms the
`nativesymbol/exists` check would have skipped them otherwise.

**What is still unconfirmed.** That the upload is *applied*.
Everything above was measured locally with the vendor's own tooling; whether
Tracer's backend then resolves Dart frames against those symbols needs a real
project and a real crash. Question 1 in
[questions-for-vendor.md](questions-for-vendor.md) asks exactly this.

One specific thing to watch. `ParsedSymbolFile` also carries an
`originalLibHash` — a hash of the file the symbols were generated from. The
staged file is the Dart symbol file, not the real `libapp.so`, so that hash
differs from the shipped library's. If the backend matches on the build id it
does not matter; if it matches on the hash, the upload will land under an
identity nothing looks up. That is the most likely way for this to fail
quietly.

Two caveats before turning it on:

* Even if it works, it helps **native** crashes and minidumps whose addresses
  land inside `libapp.so`. A Dart error reported through
  `TracerCrashReport.report` carries a *text* stack trace, and uploaded native
  symbols have nothing to bind to. It will not make manually reported Dart
  errors readable — for those, the verbatim trace plus `flutter symbolize`
  remains the route.
* The symbol file embeds absolute source paths from the build machine (for
  example `/Users/<you>/…/lib/main.dart`) and the complete set of Dart symbol
  names. Uploading it sends both to Tracer. If you obfuscated in order to keep
  those names off a server, this trade is the opposite of what you wanted.

### 3. An incremental build can silently ship without symbols — confirmed

This one bites in CI.

`flutter build apk --obfuscate --split-debug-info=build/symbols` delegates to
Gradle. When the Gradle task that runs the Dart AOT step is `UP-TO-DATE`, the
step does not run, and **the symbol file is not regenerated** — even though a
release APK is produced and the command exits 0. Delete the symbols directory
between two builds and the second build happily produces an APK with no symbol
file next to it.

On a machine or a CI runner with a warm Gradle cache, that is a release whose
crashes can never be read, and nothing in the output says so.

Guard against it. `tool/verify_build_id.sh` fails the build unless a symbol file
exists **and** its build id matches the `libapp.so` actually inside the APK:

```sh
flutter build apk --release --obfuscate --split-debug-info=build/symbols
tool/verify_build_id.sh
```

It runs on every CI build of the example, and it is worth copying into your own
release pipeline. Use `flutter clean` before a release build if you want
certainty rather than a check.

## The workflow that works today

1. **Build and verify.**

   ```sh
   flutter clean
   flutter build apk --release --obfuscate --split-debug-info=build/symbols
   tool/verify_build_id.sh
   ```

2. **Archive `build/symbols/` with the release.** Treat it like a signing
   artefact: keyed by version, retained at least as long as Tracer keeps events
   (90 days), ideally longer. The CI workflow in this repository uploads it as a
   build artefact for exactly this reason.

3. **Decode on demand.** Open the event in Tracer, copy the verbatim trace out
   of the log tab, and:

   ```sh
   flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
   ```

   The `dart.build_id` key on the event tells you which archived symbol file to
   reach for.

4. **Keep the R8 mapping upload on** (`uploadMapping = true`, the default). It
   does nothing for Dart frames, but it is what makes the Kotlin and Java halves
   of a native crash readable.

5. **Optionally, stage the Dart symbols for upload too** (finding 2), if a
   native crash inside `libapp.so` is something you expect to have to read and
   you are comfortable with the caveats:

   ```sh
   tool/prepare_dart_symbols.sh build/symbols
   ```

## Not obfuscating

A legitimate choice, and the one to make if the manual step above is not
acceptable to your team.

Without `--obfuscate`, Dart AOT stack traces keep function names and file paths,
and everything arrives in Tracer readable with no symbol file at all. The cost
is that your Dart symbol names ship inside `libapp.so`.

You can also keep `--split-debug-info` **without** `--obfuscate`: the binary
shrinks, and traces stay readable. That combination is usually the best trade
for an application that is not worried about name-level reverse engineering.

## iOS

`dSYM` upload works as documented, through Tracer's Fastlane plugin or bash
script, and it covers native frames. The vendor's script is an Xcode Run Script
phase guarded by `ACTION == install && CONFIGURATION == Release`, so it only
fires during an archive; `tool/upload_ios_dsym.sh` does the same upload from the
command line and fails closed, the way the web source-map upload does. Confirmed
against the live endpoint on 2026-08-26:
`POST https://plugin-api.apptracer.ru/api/symbol/upload?symbolToken=…` with
`versionName`, `versionCode` and a zip of the `.dSYM` bundles answered
`{"success":true}`. Dart frames are unaffected: the same
`--split-debug-info` story applies, with the same manual `flutter symbolize`
step.

Tracer's own documentation states that a `NON_FATAL` sent with
`traceType == .custom` only uses supplied symbols **when a debugger is
attached**. In a release build they are ignored. That is why the iOS
implementation puts the readable Dart trace in the attached log and synthesises
an `issueKey` for grouping rather than relying on the symbol array.

## Web

Подтверждено 26.08.2026: `tool/upload_web_sourcemaps.sh` заливает сорсмапы
release-сборки, и Tracer применяет их к событиям, пришедшим **после** загрузки.
Минифицированный кадр `main.dart.js` превращается в
`(../../../lib/main.dart:190:21) _HomePageState.build.<anonymous function>` —
имя функции и строка восстанавливаются. Пути dart2js записывает относительными,
и сопоставлению это не мешает.

Source maps do work, with two rules that are easy to get wrong:

* **Tracer matches source maps by file path, not by Debug ID.** Sentry matches
  by Debug ID; Tracer does not. If the paths inside your uploaded archive do not
  match the paths in the frames, nothing is applied and nothing tells you why.
* `versionName` in the upload must equal the `release` the SDK reports. Note
  that Tracer strips everything up to and including the last `@`, so
  `my_app@1.2.3` is stored as `1.2.3`.

```sh
flutter build web --release --source-maps
TRACER_PLUGIN_TOKEN=... tool/upload_web_sourcemaps.sh 1.0.0
```

`tool/upload_web_sourcemaps.sh` fails closed: an empty archive, a missing token,
a failed request or a response that is not `{"success":true}` all exit non-zero,
because a release that silently ships without usable source maps looks fine
right up until the first crash. The token is read from the environment and never
appears in argv, so it stays out of process listings and CI logs.

Source maps apply only to errors received **after** the upload, so upload before
you deploy — and remember there is no re-symbolication, so anything collected in
between stays unreadable.
