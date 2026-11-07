# MDX test fixtures

These binary files contain self-authored sample entries; they are not commercial dictionary data. They were generated on 2026-11-07 by `zhansliu/writemdict` at commit `f0240b30cabd2f0470d3ee1a0641fc7f8c38dcf5`, independently of the Swift reader. See `THIRD-PARTY-NOTICES.md` for the writer license.

Generation used `MDictWriter(..., title="WordNest Test Dictionary", block_size=64)` with default zlib compression, then `encrypt_index=True`, `encoding="utf16", compression_type=0`, `encoding="gbk"`, `encoding="big5"`, or `version="1.2"` as indicated by the filename. Python compatibility adjustments replaced `cgi.escape` with `html.escape` and omitted the unused Salsa20 import. No password-protected files were generated. The UTF fixtures include aliases, a cyclic alias, HTML/script/image markup, comparison punctuation, and a multilingual entry from `Assets/Fixtures/sample-text.json`. Legacy-encoding fixtures include both ASCII and Han text. Small blocks exercise multiple key and record blocks.

Tests consume the checked-in files; Python and the writer are not runtime or test dependencies. SHA-256 hashes:

- `big5-zlib.mdx`: `9cca486f776e3469d5189856ee28a758e0a7897124141c74c624c52bc2c19f34`
- `encrypted-index.mdx`: `184f3df69fab1bd66235dbd7aeb790bd1d7612a398c9597032a4350a8a071f31`
- `gbk-zlib.mdx`: `5b75f6844f3a79dca72a126fc02dcb67cb2ba4d53b42d6add8d7266e694e3deb`
- `unsupported-v1.mdx`: `e416cfb811e5c605f64d63765560f7be4f14f699e1f8540fb64fe25c3a14ecfb`
- `utf16-raw.mdx`: `dce58c3d55ded2f1a988c42244741d0b924144c69bfc215f21b7bb90f303b967`
- `utf8-zlib.mdx`: `5ef6488c535d0ccc12d2322fcfd30185c3e5552d06ac8a3778b37a3e30d193d1`
