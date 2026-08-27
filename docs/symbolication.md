# Symbolication

What happens to a Dart stack trace in a release build, what Tracer can and
cannot do about it, and what to do so you are not left holding an undecodable
crash six months from now.

Last updated: 2026-08-27.

## The problem

Build with `--split-debug-info` — with or without `--obfuscate` — and Dart
stack traces stop being text:

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

### What that means for a split-debug-info build on Android

A DWARF trace has no names, only addresses, and those move with every build.
Frames forwarded to Tracer end up as
`dart.obfuscated._kDartIsolateSnapshotInstructions+0x...`, so grouping is
**stable within a build and unstable across builds**: the same logical error
opens a new group in every release.

That is inherent to the trace format rather than a defect here — there is
nothing stable left to group by — but it is worth knowing before choosing
`--split-debug-info`. Two ways out:

* Drop `--split-debug-info` (see "Keeping traces readable" below). Traces keep
  their function names, grouping is stable across releases, and no symbol file
  is needed to read them.
* Pass an explicit `issueKey` to `Tracer.recordError` at call sites you care
  about. That pins grouping regardless of what the stack looks like.

The custom key `dart.obfuscated` is named for the case it was first met in. It
is set from whether any frame is address-only — that is, whether the event needs
`flutter symbolize` — so it reads `true` for a `--split-debug-info` build that
was never obfuscated. Read it as "needs symbolication".

## Tracer's symbol channels

Tracer documents three, and none of them is for Dart:

| Artefact | Channel |
|---|---|
| Android `mapping.txt` (R8) | `ru.ok.tracer` Gradle plugin, `uploadMapping` |
| Android native `.so` debug info | same plugin, `uploadNativeSymbols` / `additionalLibrariesPath` |
| iOS `dSYM` | Tracer's Fastlane plugin or its bash script |
| Web source maps | `POST https://plugin-api.apptracer.ru/api/sourcemap/upload` with `sourcemapToken` and `versionName` |

**There is no channel for Dart `--split-debug-info` files, documented or
otherwise.** That is the central fact of this document, and it is why decoding
an obfuscated Dart trace is a manual step. It is also the vendor's own position,
stated on 2026-08-27 in answer to a question about a Sentry-compatible
`debug-files upload`:

> В Tracer нет поддержки стектрейсов на Dart и нет никакого способа накатить
> debug-файл dart на стектрейс.

Note how wide that is. The first half — no support for Dart stack traces — has
nothing to do with obfuscation: Tracer's backend does not read a Dart trace as a
trace in any build, which is why this package parses one into Tracer's frame
model on the client and carries the verbatim text in the log. The second half,
about debug files, only costs anything when a debug file exists to apply, that
is when `--split-debug-info` is on.

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

### 2. Tracer's own `dump_syms` reads the Dart symbol file — confirmed, but the symbols are never applied

The upload half of this works and is worth understanding. The other half does
not: measured 2026-08-27, the SDK's crash reporter records `libapp.so` with a
zero build id, so nothing the backend holds can be matched to it. The measurement
and its cause are at the end of this finding; read to there before acting on any
of it.

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
it are exactly a symbol override. The vendor confirmed on 2026-08-27 that this
is what the feature was built for:

> да, можно положить libapp.so в папку, скормить ее в additionalLibrariesPath и
> оно возьмёт символы с бонусной папочной либы […] вообще все это делалось для
> сложных запросов вида «мы очень не хотим чтоб агп в принципе никогда не видел
> unstripped-либы, поэтому мы хотим способ перекрыть stripped-либы в билде
> unstripped-либами снаружи»

Which is this case exactly, with the Dart symbol file standing in for the
unstripped library.

The plugin also grades what it parses. `ParsedSymbolFile.Quality` has three
values — `BROKEN`, `CFI_ONLY`, `FULL` — and libraries without usable symbols are
skipped with "No usable symbols found for the following libraries, stacktraces
will be incomplete". The measurements above map straight onto that: the stripped
`libapp.so`, with only `PUBLIC` and `STACK CFI` records, is `CFI_ONLY`; the Dart
symbol file, with 7 545 `FUNC` entries and line tables, is `FULL`.

So the vendor's existing native-symbol channel can carry Dart AOT symbols. What
follows is how the plugin actually handles the collision, read out of the 1.4.0
bytecode, because those details decide whether the upload happens at all.

**The staged file displaces the real one; it does not join it.**
`CollectSymbolsTask.collect()` walks `merged_native_libs` first and
`additionalLibrariesPath` second, keying every file it parses by (file name,
build id). When the second walk lands on a key the first already produced, the
earlier entry is removed from the upload list and the newcomer takes its place,
with its `.sym` copied over the old one. Exactly one `libapp.so` per build id is
ever uploaded, and with staging on it is the Dart symbol file.

**No conflict warning fires, and `dontWarnOnLibraryConflicts` is unnecessary.**
Before replacing, `handleSameSymbols` compares the two: a `FULL` newcomer over a
non-`FULL` incumbent is logged "assuming symbol upgrade" at debug level and
returns. The "Multiple different copies…" warning is only for two copies that
are not ordered by quality — as the vendor puts it, «потому там варнинги на
случай конфликтов только если ожни символы не-очевидно-лучше других». Nor has
the flag disappeared, contrary to their recollection: `TracerConfig` and
`MergedTracerConfig` in 1.4.0 both carry `dontWarnOnLibraryConflicts`. Only the
warning text above spells it `dontWarnAboutLibraryConflicts`, which is the typo
reported back to them.

**The module name.** `dump_syms` takes the `MODULE` name from the file name, so
as shipped the upload would be called `app.android-arm64.symbols` rather than
`libapp.so`. Copying the file to `libapp.so` in a staging directory makes both
the name and the build id match — confirmed by re-running `dump_syms` on the
renamed copy. `ParsedSymbolFile` exposes `moduleName`, `buildId` and
`isProperBuildId`, so both are read and checked.

**`forceUploadNativeSymbols` is not needed.** It gates two separate things in
`collect()`, in this order:

1. Entries whose quality is not `FULL` are gathered into a "no usable symbols"
   list. Without the flag they are removed from the upload list; with it, the
   plugin logs "Uploading them anyway due to forced upload" and keeps them.
2. Only afterwards, and only when the flag is off, `checkSymbolsExistAtApi` asks
   `nativesymbol/exists` and drops whatever the backend already holds.

The staged Dart `libapp.so` is `FULL`, so step 1 never touches it, and nothing
else carries its (name, build id) into step 2 — the stripped copy was displaced
by the walk, and in an unstaged build step 1 would have dropped it anyway for
being `CFI_ONLY`. An unforced build uploads the Dart symbols exactly once, which
is also the vendor's advice:

> forceUpload лучше не включать, он отключает только проверку на наличие
> такихто символов на бекенде (оно по дефолту не загружает если уже есть либа с
> таким же именем и build id, ибо натив обычно нечасто пересобирают)

This corrects an earlier reading in this document. The live run of 2026-08-26
forced the upload and printed "Uploading them anyway due to forced upload", and
that line was taken here as proof that `nativesymbol/exists` would otherwise
have skipped the Dart symbols. It is not: the line belongs to step 1, and it was
about the other, genuinely symbol-less libraries in the build.

One case still wants the flag: repair. If some `libapp.so` already reached the
backend under a given build id — a forced run that sent the stripped copy, say —
the exists check will skip the good symbols and say nothing about it. Staging
from the first build of that build id avoids the situation entirely. Whether a
forced re-upload then replaces what the backend holds is not visible from the
client.

`tool/prepare_dart_symbols.sh` does the staging, keyed by build id so a
multi-ABI build does not collide:

```sh
flutter build apk --release --obfuscate --split-debug-info=build/symbols
tool/prepare_dart_symbols.sh build/symbols
# -> build/symbols/tracer-upload/<build-id>/libapp.so
```

then point the Gradle plugin at it:

```groovy
tracer {
    create('defaultConfig') {
        additionalLibrariesPath = "$projectDir/../build/symbols/tracer-upload"
    }
}
```

The parent directory is enough for a build covering several architectures: the
walk is recursive and the entries are keyed by (name, build id), so the three
staged copies stay apart.

The example wires this up behind an environment variable:

```sh
DART_SPLIT_DEBUG_INFO=$PWD/build/symbols/tracer-upload \
flutter build apk --release -Ptracer.enabled=true \
  --obfuscate --split-debug-info=build/symbols
```

**Upload confirmed 2026-08-26.** Against a live project the plugin logged
`Uploading libapp.so:<build-id>` for all three staged architectures, with ids
matching the staged files, and the build succeeded.

**Matching is by build id — answered 2026-08-27.** This was the open question,
and the way the scenario was most likely to fail quietly: `ParsedSymbolFile`
carries an `originalLibHash`, and the staged file is not the shipped library, so
that hash differs. The vendor:

> сопоставление как у minidump-stackwalk - по этим типаууидам от
> .note.gnu.build-id, сценарий должен сработать

The bytecode closes the rest of it. `originalLibHash` is a SHA-1 of the file
`dump_syms` read, it is computed only inside `handleSameSymbols` to decide
whether two copies are the same file, and it is never part of the upload.
Nothing derived from the file's contents reaches Tracer at all; the identity is
the `MODULE` id, which both files carry identically because both carry the same
`.note.gnu.build-id`.

**And they are still not applied. Measured 2026-08-27 — the scenario does not
work today.** «Сценарий должен сработать» was the vendor's considered opinion;
this is the measurement, and it disagrees. The cause is on the client, in the
SDK's own crash reporter, and it makes the whole channel unusable for Dart no
matter what is uploaded.

The test needed a crash whose faulting instruction is *inside* Dart AOT code —
the example's `crashInsideDartCode` stores through a `dart:ffi` pointer to an
unmapped address, which compiles to a plain instruction in
`_kDartIsolateSnapshotInstructions`. A signal raised from Kotlin does not do:
it unwinds through libc and ART, and its report carries no `libapp.so` frame to
symbolicate.

Three runs, one build id, symbols uploaded before all of them:

| run | module in the report | offset | debug id |
|---|---|---|---|
| default packaging | `base.apk` | `0xa5234` | `000…0` |
| `useLegacyPackaging = true` | `libapp.so` | `0xa5234` | `000…0` |
| the same, plus the first `PT_LOAD` patched to `r-x` | `libapp.so` | `0xa5234` | `000…0` |

None can match: the upload is keyed `libapp.so` / `F99DCFDB6338…30`. Packaging
fixes the module *name* and nothing else.

Both symptoms have one cause. Tracer's reporter identifies a module by **the
mapping the faulting address falls in**, and reads the ELF identity from that
mapping's start. `libapp.so` is mapped in pieces, one per `PT_LOAD`, and the
code lives at file offset `0xb0000`; the mapping holding the crash therefore
begins in the middle of the file, where there is neither an ELF header nor a
`.note.gnu.build-id`. Hence the zero id, and hence a module base short by
exactly the code segment's offset: `0x155234 - 0xb0000 = 0xa5234`, the number in
the report.

The program headers say which libraries this hits:

| library | code at file offset | build-id note |
|---|---|---|
| `libapp.so` | `0xb0000` | `0x1c8` — in a different mapping |
| `libflutter.so` | `0x454080` | `0x270` — in a different mapping |
| `libtracernative.so` | `0x0` | `0x238` — in the same mapping as the code |

Any library whose code is not at file offset 0 loses its identity, which is why
`libapp.so` and `libflutter.so` are the two zero-id modules in the report while
the vendor's own `libtracernative.so` is fine.

**There is no workaround on the application's side; this was measured, not
assumed.** The obvious candidate was the segment layout: make the first
`PT_LOAD` executable, so that the lowest executable mapping of the file starts
at offset 0 and carries the ELF header. Patching `p_flags` from `r--` to `r-x`
in the shipped `libapp.so`, re-zipping and re-signing produced an app that runs
normally — and a report byte for byte identical to the one before it, zeros and
`0xa5234` included. The reporter never looks at the file's other mappings. Upstream
breakpad handles this by subtracting the mapping's file offset before reading
the ELF; whatever Tracer's reporter is built from does not.

So even a matching id would not be enough: every address is `0xb0000` short,
and the names resolved would be the wrong ones.

**What this means in practice.** Staging Dart symbols has no effect. The upload
works, the vendor's matching rule is the right one, and the client never
produces anything to match — so `flutter symbolize` on the archived symbol file
remains the only way to read an obfuscated Dart trace on Android.

The vendor closed the question from the other end on 2026-08-27: «В Tracer нет
поддержки стектрейсов на Dart и нет никакого способа накатить debug-файл dart на
стектрейс». Read against the answer of the same day about
`additionalLibrariesPath` («перекрывать/добавлять через такое можно, да»), the
two are about different things — the native uploader will take any breakpad
`.sym`, and the product has no Dart symbolication — and the measurement above
sits with the second. So this is not a scenario waiting on a fix.

The zero build id is still reported back as a defect in
[questions-for-vendor.md](questions-for-vendor.md), because it is not about Dart:
it costs every Flutter application its `libflutter.so` frames. If it is fixed,
check 16 in [live-verification-plan.md](live-verification-plan.md) re-runs in
minutes, since everything else in the chain is proven — but a passing check 16
would be a side effect of that repair, not a supported route.

Two caveats, if you enable the staging anyway:

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

### 4. `--split-debug-info` alone makes traces address-only — `--obfuscate` is not what does it — confirmed

This corrects the earlier text of this document, which said in two places that a
build with `--split-debug-info` but without `--obfuscate` keeps readable traces.
It does not.

The flag is passed to `gen_snapshot` by `flutter_tools`, and the two options are
independent — `packages/flutter_tools/lib/src/base/build.dart`, Flutter 3.35.7:

```dart
genSnapshotArgs.addAll(<String>[
  if (shouldSplitDebugInfo) ...<String>[
    '--dwarf-stack-traces',
    '--resolve-dwarf-paths',
    '--save-debugging-info=...',
  ],
  if (dartObfuscation) '--obfuscate',
]);
```

`--dwarf-stack-traces` is what stops function names being written into the
snapshot for stack traces, and it hangs on `--split-debug-info` alone.

Measured 2026-08-27, three release builds of the same throwaway app on one
Android 15 arm64 emulator, each printing the stack of a caught `StateError`
raised through three `@pragma('vm:never-inline')` functions:

| build | first frame |
|---|---|
| `--release` | `#0 innermostProbeFunction (package:dwarf_probe/main.dart:5)` |
| `--release --split-debug-info` | `#00 abs 0000006ebd670993 virt 0000000000216993 _kDartIsolateSnapshotInstructions+0x160053` |
| `--release --obfuscate --split-debug-info` | `#00 abs 0000006f44b9e6ff virt 00000000002066ff _kDartIsolateSnapshotInstructions+0x15fdbf` |

The last two are the same format, `build_id:` header and all. Obfuscation
changes the addresses, because it changes the code layout, and nothing else that
is visible in a trace.

`flutter symbolize` decodes the unobfuscated DWARF trace against that build's
symbol file exactly as it does the obfuscated one, down to the column:

```
#0      innermostProbeFunction (.../dwarf_probe/lib/main.dart:5:3)
#1      middleProbeFunction (.../dwarf_probe/lib/main.dart:9:31)
```

So the archive-the-symbol-file rule of this document applies to **every**
`--split-debug-info` build, not only obfuscated ones.

The same three builds also settle what each flag keeps out of the shipped
library. Grepping the `libapp.so` inside each APK for the probe function's name:

| build | `innermostProbeFunction` in `libapp.so` | size |
|---|---|---|
| `--release` | present | 2 753 456 |
| `--release --split-debug-info` | absent | 2 360 240 |
| `--release --obfuscate --split-debug-info` | absent | 2 294 704 |

Both symbol files contain the real name, which is why `flutter symbolize`
resolves it in either build. So `--split-debug-info` alone already takes Dart
function names out of the binary; `--obfuscate` on top renames what is left and
saves a further 65 KB here, and neither difference is visible in a stack trace.

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

5. **Do not stage the Dart symbols for upload.** The channel accepts them
   (finding 2) but the SDK's crash reporter records `libapp.so` with a zero
   build id and a shifted base, so nothing is ever matched against them —
   measured 2026-08-27. The vendor states plainly that Tracer has no Dart
   symbolication at all, so this is not a fix to wait for.
   `tool/prepare_dart_symbols.sh` and the wiring around it are kept as evidence
   for the defect report and in case the module-identity bug is repaired;
   running them today only sends your source paths and Dart symbol names to a
   server for no return.

## Keeping traces readable

A legitimate choice, and the one to make if the manual step above is not
acceptable to your team. It has exactly one requirement, and it is not the one
this document used to state: **build without `--split-debug-info`.**

Then Dart AOT stack traces keep function names and file paths, and everything
arrives in Tracer readable with no symbol file at all. The cost is that your
Dart symbol names ship inside `libapp.so`, and the binary is larger by the
debug information.

`--split-debug-info` on its own, without `--obfuscate`, does **not** buy you
readable traces: it is the flag that turns them into addresses. See finding 4.
Obfuscation on top of it changes what is written into the symbol file, not what
the trace looks like.

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
