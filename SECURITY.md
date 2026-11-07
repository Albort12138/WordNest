# Security policy

## Reporting a vulnerability

Please report suspected security vulnerabilities privately to [albort.yao.xue@gmail.com](mailto:albort.yao.xue@gmail.com), maintained by Albort. Do not open a public issue containing exploit details, private vocabulary, Notes content, credentials, or screen captures of unrelated information.

Include the affected WordNest version or commit, macOS version, reproduction steps, expected impact, and a minimal sanitized example when possible. Please say whether you used an official release or a local source build. The maintainer will coordinate investigation and disclosure by email; no fixed response or resolution time is promised.

For ordinary recognition, dictionary, display, or setup problems, use the [issue tracker](https://github.com/Albort12138/wordnest/issues) after removing personal information.

## Supported versions

Security fixes target the latest published release and the current development branch. Older preview builds are not maintained as separate security branches. Check [GitHub Releases](https://github.com/Albort12138/wordnest/releases) for available versions; the presence of a download is not a claim that every macOS version or source application has been tested.

## Security and privacy boundaries

WordNest processes captured screen images locally and does not operate an application backend or automatically upload vocabulary. Its sensitive capabilities are macOS screen capture, optional Accessibility access for source-page metadata, and Automation access for the selected Notes destination and supported browser metadata.

Apple Notes may synchronize through iCloud when the selected account uses it. macOS dictionaries and voices are separate system resources. These system behaviors are outside WordNest's own no-upload promise. Consult the product README and privacy documentation for the current feature scope.

Only share diagnostic information after reviewing it. Application paths, source URLs and titles, account or folder names, screenshots, and exported collection histories can reveal personal information even when no authentication secret is present.

## Builds and credentials

Use release packages from this repository's official release page or build from a revision you have reviewed. A successful signature-integrity check on an ad-hoc development build does not establish the maintainer's identity or Apple notarization.

Never include signing certificates, private keys, notarization credentials, environment secrets, or private Notes exports in a commit, issue, or pull request. If a secret is exposed, revoke or rotate it; removing it from the current file does not remove prior copies.
