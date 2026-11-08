# Installing WordNest

English · [简体中文](INSTALL.zh-CN.md)

WordNest is free and open source. The first distribution is **ad-hoc signed and not notarized by Apple**; no paid Apple developer membership is required to build it. An ad-hoc signature is a local code-integrity signature, not verified developer identity or an Apple security review. Download only from [the official repository's Releases](https://github.com/Albort12138/WordNest/releases). A candidate version does not establish that a download has been published.

## Requirements and verification

Use an Apple Silicon Mac running macOS 14 or later. Intel packages are not provided. Download the `.dmg` ending in `-unnotarized.dmg`, its `-SHA256SUMS.txt`, and optionally `-build-info.txt`. The ZIP is an alternative containing the same app and documents.

In Terminal, change to the download directory and verify the DMG (replace filenames with those of your download):

```sh
shasum -a 256 WordNest-26.1.0-build1-macos-arm64-unnotarized.dmg
```

Compare the complete output hash with the matching filename in the published checksum file. A checksum detects download corruption; it does not independently prove the publisher's identity or establish that an app is safe.

## Install and first launch

1. Quit an existing WordNest before updating. Open the DMG and drag **WordNest.app** into **Applications**, replacing the older copy if intended. Eject the DMG.
2. Open **Applications → WordNest**. Always run the installed copy before granting permissions.
3. macOS may say Apple cannot check the app or the developer cannot be verified. If you trust this exact download, follow [Apple's instructions for an app-specific exception](https://support.apple.com/en-us/102445): after attempting to open it, open **System Settings → Privacy & Security**, find the message for WordNest, click **Open Anyway**, and confirm **Open** if offered. You may need administrator authorization. System versions and managed Macs can differ; this is not a guaranteed bypass.
4. If macOS reports malware, revoked authorization, or a damaged app, stop. Verify the download and report the exact message. Do not treat every alert as an unidentified-developer warning.
5. Choose the interface language on WordNest's first page; **System default** is selected initially. Continue through setup, approving only the permissions for the features you want.

Do not disable Gatekeeper/SIP, change global security policy, or remove quarantine attributes. If the system does not offer an exception, build from reviewed source or report the environment and alert instead.

## Permissions and updates

Screen Recording enables on-device screenshot OCR. Notes automation enables vocabulary saving and browsing. Safari automation and Accessibility enable optional source capture in supported windows. These permissions are separate from Gatekeeper approval and must be granted by you.

If macOS asks to quit and reopen, let it do so. If it only quits, reopen the same installed copy; WordNest retains the unfinished setup step. An update's ad-hoc signature can change, so existing privacy grants may need to be renewed. Keep the installation location stable and inspect WordNest's Settings if lookup or integrations stop working. Do not reset system-wide permissions. Installing an update does not itself delete your Apple Notes vocabulary.

Automatic updates are not implemented. Download the next release and replace the app while it is quit. Source compilation instructions are in the [README](https://github.com/Albort12138/WordNest/blob/main/README.md#build-from-source).
