# Third-party notices

WordNest software code and documentation are distributed under the MIT License. The owl artwork is excluded and covered by `Assets/Branding/LICENSE` (bundled as `WordNest-artwork-LICENSE.txt`). macOS frameworks and zlib are supplied by the operating system and retain their respective terms. No third-party dictionary content is bundled, apart from the self-authored test entries described below.

## MDX format documentation and test writer

The independent Swift MDX reader follows the container description in [zhansliu/writemdict](https://github.com/zhansliu/writemdict/tree/f0240b30cabd2f0470d3ee1a0641fc7f8c38dcf5). Binary fixtures in `Tests/Fixtures/` were generated with its writer using self-authored WordNest test data. The Python writer is not included in the app or required at runtime.

The MIT License (MIT)

Copyright (c) 2015 zhansliu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## RIPEMD-128 key-index transform

`Sources/RIPEMD128.swift` adapts the round tables and algorithm in [Feng Dihai's ripemd128.js](https://github.com/fengdh/mdict-js/blob/efc3fa368edd6e57de229375e2b73bbfe189e6ee/ripemd128.js), which explicitly declares the MIT License. The source credits coiscir/jsdigest and the RIPEMD-128 designers Hans Dobbertin, Antoon Bosselaers, and Bart Preneel (1996). This transform provides MDX file compatibility and is not used as an application security primitive.

Copyright (c) 2015 Feng Dihai <fengdh@gmail.com>
Copyright (c) 2009-2011 Jonathan Lonowski (coiscir/jsdigest)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.



Imported dictionary files remain subject to their own licenses. Importing or using a file does not grant redistribution rights; WordNest does not download or redistribute Eudic dictionaries.
