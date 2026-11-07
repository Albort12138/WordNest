import Foundation

/// RIPEMD-128 for the MDX key-index transform, not for password storage or security decisions.
/// Round tables and algorithm adapted from Feng Dihai's MIT-licensed ripemd128.js (2015),
/// based on coiscir/jsdigest. Attribution and the MIT grant are in THIRD-PARTY-NOTICES.md.
enum RIPEMD128 {
    static func hash(_ input: Data) -> [UInt8] {
        let order = [
            Array(0..<16), [7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8],
            [3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12], [1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2],
            [5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12], [6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2],
            [15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13], [8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14]
        ]
        let shifts = [
            [11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8], [7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12],
            [11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5], [11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12],
            [8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6], [9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11],
            [9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5], [15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8]
        ]
        let constants: [UInt32] = [0,0x5a827999,0x6ed9eba1,0x8f1bbcdc,0x50a28be6,0x5c4dd124,0x6d703ef3,0]
        func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            switch round {
            case 0: return x ^ y ^ z
            case 1: return (x & y) | (~x & z)
            case 2: return (x | ~y) ^ z
            default: return (x & z) | (y & ~z)
            }
        }
        func rotate(_ x: UInt32, _ n: Int) -> UInt32 { (x << n) | (x >> (32 - n)) }
        var bytes = [UInt8](input)
        let bits = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes += (0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        var h: [UInt32] = [0x67452301,0xefcdab89,0x98badcfe,0x10325476]
        for start in stride(from: 0, to: bytes.count, by: 64) {
            let words: [UInt32] = (0..<16).map { i in
                let p = start + i * 4
                return UInt32(bytes[p]) | (UInt32(bytes[p+1]) << 8) | (UInt32(bytes[p+2]) << 16) | (UInt32(bytes[p+3]) << 24)
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var aa = a, bb = b, cc = c, dd = d
            for round in 0..<4 {
                for j in 0..<16 {
                    let t = rotate(a &+ f(round,b,c,d) &+ words[order[round][j]] &+ constants[round], shifts[round][j])
                    a = d; d = c; c = b; b = t
                    let u = rotate(aa &+ f(3-round,bb,cc,dd) &+ words[order[round+4][j]] &+ constants[round+4], shifts[round+4][j])
                    aa = dd; dd = cc; cc = bb; bb = u
                }
            }
            let t = h[1] &+ c &+ dd
            h[1] = h[2] &+ d &+ aa; h[2] = h[3] &+ a &+ bb; h[3] = h[0] &+ b &+ cc; h[0] = t
        }
        return h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    }
}
