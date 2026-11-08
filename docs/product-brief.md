# Product brief

## Purpose

WordNest helps Mac users learn vocabulary while watching subtitled videos or reading text that cannot be selected. Point at a word, invoke a shortcut, read a definition, optionally play its pronunciation, and deliberately save it to Apple Notes.

The initial product is a lightweight menu-bar application. It does not require an account, a translation server, a browser extension, or a separate vocabulary database.

## Primary workflow

1. Install the app in Applications and complete guided first-launch setup.
2. Point at visible text and press **Control + Option + D**.
3. Review the recognized word, dictionary definition, pronunciation and original OCR line.
4. Check the optional page title/link; edit missing or incorrect metadata before saving.
5. Save to the selected Notes location and review vocabulary in WordNest or Notes.

An intentional new collection increases the count. Duplicate clicks, retries and readback of the same collection event must not increase it. A new context is retained without replacing existing definitions or the first-collection date.

## Local processing and storage

OCR, dictionary lookup and speech use system services on the Mac. WordNest does not automatically upload screen content or vocabulary, and does not operate its own synchronization service. The capture frame is processed in memory rather than stored as an image.

Notes is the vocabulary source of truth. Choosing an iCloud Notes account allows Apple's own synchronization; choosing an available On My Mac account keeps that notebook local. Local transaction metadata supports safe retry handling and is not a second copy of the vocabulary content. See [PRIVACY.md](../PRIVACY.md).

## Product boundaries

| Capability | Boundary |
| --- | --- |
| OCR | Visible, capturable text; timing, size, contrast and language affect recognition |
| Definitions | Installed/active system dictionaries; Chinese meanings are not guaranteed for every language |
| Speech | Installed matching system voices; missing resources need system setup |
| Automatic source links | Safari and compatible Safari Dock web-app metadata; other apps may require manual links |
| Notes writing | Selected non-shared physical folder; a smart folder can be a separate browsing view |
| Statistics | Deliberately saved words and collection events, not total video vocabulary or viewing frequency |
| Fullscreen | Must be validated by application and mode; no universal overlay guarantee |
| UI | System default, English or Simplified Chinese; bilingual README documentation |

The preview targets Apple Silicon and macOS 14+. Earlier real use was on an M3 Mac running macOS 26. Other configurations remain acceptance work.

## Permissions and first launch

Setup explains and requests screen capture, plus optional source-link and Notes permissions. macOS controls consent: installation cannot silently pregrant it. Optional integrations can be skipped without disabling dictionary lookup once screen permission is effective. Denied required capture access is clearly shown as unavailable, even if the introduction is dismissed.

## Distribution and licensing

The intended download channel is [GitHub Releases](https://github.com/Albort12138/wordnest/releases), with clearly labeled, ad-hoc-signed unnotarized packages requiring no paid developer membership. Signed/notarized distribution remains optional. A first official release remains pending. Source builds are available for development and may need separate system authorization.

WordNest is free and open-source software under the [MIT License](../LICENSE). Use, modification and redistribution, including commercial use, require no separate authorization or fee; preserve the copyright and license notices. Code and documentation contributions use the same license without a separate contributor agreement. The owl artwork is excluded from MIT; see the [separate artwork license](../Assets/Branding/LICENSE). Modified distributions must replace the artwork or obtain written permission.

## Local dictionary selection

The initial candidate supports the system provider and explicitly imported MDX 2.x files. Definitions remain in the WordNest card; dictionary selection is separate from OCR language. No Eudic private-storage access, external-app control, hosted translation or bundled commercial dictionary content is required. See README for supported file variants and limits.
