# Contributing to WordNest

Thank you for helping improve WordNest. WordNest is free and open-source software under the [MIT License](LICENSE).

## Ways to contribute

We welcome code contributions, bug reports, reproducible usage examples, documentation improvements, and suggestions about the learning workflow. Before a large proposal, open an [issue](https://github.com/Albort12138/wordnest/issues) so its scope can be discussed.

For bugs, include the WordNest version, macOS version, Mac architecture, source application, whether the video was fullscreen, expected behavior, actual behavior, and minimal reproduction steps. Distinguish OCR failures, missing dictionary definitions, source-link capture failures, and Notes write failures. Review screenshots and logs before sharing: they may reveal vocabulary, video links, account names, or unrelated screen content.

Report security vulnerabilities privately using [SECURITY.md](SECURITY.md).

## Licensing of contributions

Unless explicitly stated otherwise and agreed before submission, contributions you submit for inclusion are offered under the project's MIT License. You retain copyright in your contributions; no copyright assignment or separate contributor license agreement is required.

Submit only work you have the right to contribute under these terms. Keep required third-party copyright and license notices, and identify any material under another license so compatibility can be reviewed before merging.

The bundled owl artwork is excluded from MIT; see [its separate license](Assets/Branding/LICENSE). Do not submit changes to that artwork without agreement from the maintainer. Software contributions remain MIT-licensed. Distribute modified apps with your own authorized artwork unless you have written permission to use the WordNest artwork.

## Local development

See the default [README](README.md) for supported systems and the current build and test commands. The scripts use Apple's command-line tools and system frameworks; no third-party runtime package is required.

- Keep application, test, script and configuration source in English, including comments and interface keys. Put translations and multilingual sample content in the appropriate bundled data resources.
- Preserve persisted Notes column headers, management markers, and compatibility identifiers in `Assets/Compatibility/legacy-notes.json` unless a change explicitly handles migration. Do not translate existing stored vocabulary when changing the source language.
- Keep builds, caches, screenshots, diagnostic reports, signing credentials, and personal Notes exports out of Git.
- Run the documented logic tests and build checks for your change. Report what you actually tested; a successful build does not prove real fullscreen, multi-display, permission, or Notes behavior.
- Tests that write to Notes must use an explicitly selected, isolated test destination. Do not run write-capable integration modes against a real vocabulary notebook.
- Keep changes focused and explain the user-visible behavior, compatibility implications, and validation in the pull request.

## Maintainer and release boundaries

Official release packages are published through [GitHub Releases](https://github.com/Albort12138/wordnest/releases). Local source builds may use a different signing identity and may require their own macOS permissions. Do not disable Gatekeeper or other system protections to make a contribution work.

For contribution questions, open an [issue](https://github.com/Albort12138/wordnest/issues). Use [SECURITY.md](SECURITY.md) for private security reports.
