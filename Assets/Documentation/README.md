# Documentation visuals

## Workflow illustration

`lookup-flow.svg` is an editable, self-contained illustration with sample content. It is not an application screenshot. It contains no externally loaded images, scripts or fonts.

## Real-app walkthrough

`wordnest-demo.gif` is a 28-second, silent sequence assembled from six real app screenshots. Frames were cropped, resized, held for readability and captioned; the sequence is not a continuous or real-time screen recording. UI content and results were not redrawn or simulated. The interface shown is Simplified Chinese; the captions are English.

The demonstration used an installed WordNest 26.1.0 build 1 candidate on the development Mac:

1. A self-authored Safari page drew a subtitle as canvas pixels: `Small changes create lasting happiness.` The user pointed at `happiness` and pressed Control + Option + D.
2. WordNest recognized the word and original line and displayed a system dictionary entry.
3. The pronunciation button was clicked; the real card displayed its speaking state. The GIF contains no audio.
4. `https://example.com/wordnest-demo` and its sample title were entered manually. Automatic Safari source access was not granted for this scenario; the footage does not demonstrate automatic source capture.
5. One deliberate collection was saved into a newly created ordinary Notes folder named `WordNest Demo`.
6. WordNest read back one word and one collection event with the original line and sample source. The same single-row table was verified in a separate Apple Notes window.

The everyday save/browse destination was restored after the demonstration. No existing vocabulary was collected again or edited. The isolated demonstration note was retained separately. An iCloud account was used for the test folder; Notes synchronization is independent of WordNest's on-device processing.

Only the self-authored sample, its generated record and the relevant app windows are included. Other Notes folders, account details, browser history and unrelated desktop content are excluded. This demonstrates one tested scenario, not universal OCR, full-screen, language, or source compatibility. Raw captures and local editing intermediates are development artifacts and are not part of the public repository.

## Rights

The workflow SVG, explanatory text and self-authored sample are covered by the repository's MIT License. The walkthrough shows application and system UI; dictionary definitions and macOS UI retain their respective rights. The owl artwork, where reproduced, remains subject to `../Branding/LICENSE`. No rights to independently reuse that character are granted by publishing these documentation visuals.
