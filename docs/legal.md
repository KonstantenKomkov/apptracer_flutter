# Licensing and naming

## This package

MIT, see [LICENSE](../LICENSE). It is an independent, unofficial integration.

**It is not affiliated with, endorsed by, or supported by VK or OK.TECH.** The
name `apptracer_flutter` describes what it integrates with while keeping it
clear that it is a third-party wrapper: it is not `tracer_sdk`, not `ok_tracer`,
not `vk_tracer`, and it carries no vendor branding. The package description, the
README and the pub.dev page all say so in the first sentence.

The name `tracer` on pub.dev is already taken by an unrelated Dart logger
(`github.com/JHubi1/tracer`) and has nothing to do with this service.

## The vendor SDKs

| SDK | License | Notes |
|---|---|---|
| `ru.ok.tracer:*` (Android) | Tracer's License Agreement, <https://apptracer.ru/license/> | declared in the published POM |
| `OKTracer` (iOS) | the same agreement | the repository `LICENSE` is one line pointing at the same URL |
| `@apptracer/sdk` (JavaScript) | ISC | declared in the npm registry metadata |

## Reading of the Tracer License Agreement

Read in the edition dated **29 May 2025**. The text is not quoted here in full:
clause 3.4 puts the documentation on the site under the Licensor's exclusive
rights, and clause 4.1 of the closing section lets the Licensor change the
agreement at any time without notice, so a copy in this repository would be both
presumptuous and stale. Read the current text at
<https://apptracer.ru/license/> — note that the page renders client-side, so a
plain HTTP client returns only the JavaScript shell.

The Licensee under the agreement is **the application developer**, not this
package: clause 2.2 makes acceptance the act of clicking "Создать" on the site,
and clause 5.1 requires registration before the Library may be used at all.
Anyone using this package registers with Tracer, accepts the agreement, and
obtains their own `appToken` before anything works.

### Why publishing this wrapper is consistent with the agreement

Four clauses govern the question, and the package is clear of each:

* **4.2.1 — no reproduction or distribution of elements of the Library.**
  This package redistributes nothing. There is no vendored AAR, no bundled
  `xcframework`, no copied source. On Android the SDK is a `compileOnly`
  dependency that the host application adds itself; on iOS the podspec declares
  `OKTracer` and CocoaPods fetches the binary from the vendor's own servers.
  This was the reason for that design, and the agreement confirms it was the
  right one.

* **4.2.3 — no sublicensing or other transfer of the granted rights.**
  Nothing is transferred. Each user is a Licensee in their own right under 2.2
  and 5.1, and obtains the Library through the vendor's own distribution
  channels on the vendor's own terms.

* **4.2.4 — the Library may not be used as the basis for a product with the
  same functionality.** This package is not such a product. It has no crash
  collection of its own on Android or iOS: it forwards Dart errors *into* the
  Library, which does the collecting, and sends them to the vendor's own
  service. It requires the Library rather than replacing it, and it makes the
  service more useful rather than substituting for it.

* **4.1 — permitted use** is "использовать основной функционал Библиотеки для
  сбора данных о мобильном приложении Лицензиата, с возможностью копирования и
  интеграции (установки) Библиотеки в мобильное приложение Лицензиата". That is
  exactly what a user of this package does: integrates the Library into their
  own application to collect data about their own application.

**There is no trademark or naming clause anywhere in the agreement.** Use of the
name "Tracer" by a third party is therefore governed by ordinary trademark law
rather than by this contract, and the standard safe posture applies — a name
that describes the integration rather than claiming to be the vendor's, plus a
prominent statement that the package is unofficial. Both are in place.

### Clause 4.2.4 — asked, and answered

Clause 4.2.4 is worded broadly enough ("продукт, содержащий такую же
функциональность") that a conservative reading could be stretched to cover any
package whose subject matter is crash reporting. The reading above — that the
clause targets building a rival SDK out of theirs, not building an adapter into
theirs — matches the rest of the agreement, but on its own it was a reading
rather than a certainty, and it was the one thing blocking publication.

**Answered 2026-08-27: the vendor does not object.** Question 2 was put to them
as written in [questions-for-vendor.md](questions-for-vendor.md) — that the
package distributes none of their artefacts, that every user registers with
them and accepts the agreement themselves, and that 4.2.4 is read as barring a
rival SDK rather than an integration wrapper. They raised no objection, to the
reading or to the name `apptracer_flutter`.

One caveat about this record: the answer is summarised here rather than quoted,
because it came through the maintainer rather than into this repository. For a
licence question the exact wording is the artefact — if the message still
exists, paste it into this section verbatim, with its date and channel.

### The Sentry-protocol transport is outside the agreement

`apptracer_flutter_http` does not use the Library at all. It posts Sentry
envelopes to Tracer's ingest, which is the vendor's own documented and
recommended route for platforms that have no Tracer SDK. Clause 4.2.4 cannot
apply to something that does not use the Library as a basis.

One wrinkle worth noticing: the agreement describes the Library throughout as
being for **mobile** applications (clauses 1.1, 4.1), while the product plainly
supports web through the JavaScript SDK and JS projects. The text appears to
lag the product. It does not affect this package, whose web path does not
touch the Library.

## Obligations this package's users inherit

Two clauses create real duties for anyone shipping an application with Tracer,
and they shape how this package behaves by default. See
[privacy.md](privacy.md).

* **1.2** — the application developer is the data controller and entrusts
  processing of end-user personal data to VK as processor.
* **1.3** — the developer **undertakes to obtain the end-user consents required
  by applicable law** for that processing.

That obligation is why `TracerOptions.isCollectionEnabled` exists as a
before-first-frame switch and why `Tracer.stopCollection()` genuinely stops
native collection rather than merely muting Dart.

## Conclusion

Publishing is consistent with the agreement as written. Confirm question 2 with
the vendor first; if their answer contradicts the reading above, do not publish
and keep the work as a private integration.
