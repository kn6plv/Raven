// SHA-512 implementation for ucode (OpenWRT)
// 64-bit values represented as [high32, low32] pairs.
// No >>> operator used; no forward function references; loops unrolled where practical.

import * as struct from "struct";

// ---------- 64-bit helper functions ----------

// Logical right shift of a 32-bit value by n bits (replaces >>>)
function shr32(x, n) {
	if (n == 0) return x & 0xFFFFFFFF;
	// Mask to unsigned 32-bit, then divide by 2^n and floor
	const xu = x & 0xFFFFFFFF;
	// For logical right shift: treat as unsigned via masking
	// (xu >> n) in ucode may do arithmetic shift, so we mask off sign-extended bits
	const result = (xu >> n) & (0xFFFFFFFF >> n);
	// But if xu had bit 31 set and >> is arithmetic, the top bits get filled with 1s.
	// Masking with (0xFFFFFFFF >> n) would also be arithmetic... so do it differently:
	// Use the identity: logical_right_shift(x, n) = ((x >> n) & ((1 << (32 - n)) - 1))
	if (n >= 32) return 0;
	const mask = (n == 0) ? 0xFFFFFFFF : ((1 << (32 - n)) - 1) & 0xFFFFFFFF;
	return (xu >> n) & mask;
}

// 64-bit addition (mod 2^64): a = [ah, al], b = [bh, bl]
function add64(a, b) {
	const lo = (a[1] & 0xFFFFFFFF) + (b[1] & 0xFFFFFFFF);
	const carry = shr32(lo, 32) ? 1 : 0;
	// Actually carry is whether lo > 0xFFFFFFFF
	const lo32 = lo & 0xFFFFFFFF;
	const hi = ((a[0] & 0xFFFFFFFF) + (b[0] & 0xFFFFFFFF) + (lo > 0xFFFFFFFF ? 1 : 0)) & 0xFFFFFFFF;
	return [hi, lo32];
}

// 5-way 64-bit addition
function add64_5(a, b, c, d, e) {
	let lo = (a[1] & 0xFFFFFFFF) + (b[1] & 0xFFFFFFFF) + (c[1] & 0xFFFFFFFF) + (d[1] & 0xFFFFFFFF) + (e[1] & 0xFFFFFFFF);
	let hi = (a[0] & 0xFFFFFFFF) + (b[0] & 0xFFFFFFFF) + (c[0] & 0xFFFFFFFF) + (d[0] & 0xFFFFFFFF) + (e[0] & 0xFFFFFFFF);
	// Carry from lo to hi: lo can be at most 5*(2^32-1), fits in double precision
	hi += (lo - (lo & 0xFFFFFFFF)) / 4294967296;
	return [hi & 0xFFFFFFFF, lo & 0xFFFFFFFF];
}

// 64-bit bitwise AND
function and64(a, b) {
	return [(a[0] & b[0]) & 0xFFFFFFFF, (a[1] & b[1]) & 0xFFFFFFFF];
}

// 64-bit bitwise XOR
function xor64(a, b) {
	return [(a[0] ^ b[0]) & 0xFFFFFFFF, (a[1] ^ b[1]) & 0xFFFFFFFF];
}

// 64-bit bitwise XOR of three values
function xor64_3(a, b, c) {
	return [(a[0] ^ b[0] ^ c[0]) & 0xFFFFFFFF, (a[1] ^ b[1] ^ c[1]) & 0xFFFFFFFF];
}

// 64-bit bitwise NOT
function not64(a) {
	return [(~a[0]) & 0xFFFFFFFF, (~a[1]) & 0xFFFFFFFF];
}

// 64-bit right shift by n bits (0 < n < 64), logical
function shr64(x, n) {
	if (n == 0) return [x[0] & 0xFFFFFFFF, x[1] & 0xFFFFFFFF];
	if (n < 32) {
		const hi = shr32(x[0], n);
		const lo = (shr32(x[1], n) | ((x[0] & ((1 << n) - 1)) << (32 - n))) & 0xFFFFFFFF;
		return [hi, lo];
	}
	if (n == 32) return [0, x[0] & 0xFFFFFFFF];
	// n > 32 && n < 64
	return [0, shr32(x[0], n - 32)];
}

// 64-bit right rotate by n bits (0 < n < 64)
function rotr64(x, n) {
	const xh = x[0] & 0xFFFFFFFF;
	const xl = x[1] & 0xFFFFFFFF;
	if (n == 0) return [xh, xl];
	if (n < 32) {
		const rh = (shr32(xh, n) | ((xl & ((1 << n) - 1)) << (32 - n))) & 0xFFFFFFFF;
		const rl = (shr32(xl, n) | ((xh & ((1 << n) - 1)) << (32 - n))) & 0xFFFFFFFF;
		return [rh, rl];
	}
	if (n == 32) return [xl, xh];
	// n > 32 && n < 64
	const m = n - 32;
	const rh = (shr32(xl, m) | ((xh & ((1 << m) - 1)) << (32 - m))) & 0xFFFFFFFF;
	const rl = (shr32(xh, m) | ((xl & ((1 << m) - 1)) << (32 - m))) & 0xFFFFFFFF;
	return [rh, rl];
}

// ---------- SHA-512 functions ----------

// Ch(x, y, z) = (x AND y) XOR (NOT x AND z)
function ch64(x, y, z) {
	return [
		((x[0] & y[0]) ^ ((~x[0]) & z[0])) & 0xFFFFFFFF,
		((x[1] & y[1]) ^ ((~x[1]) & z[1])) & 0xFFFFFFFF
	];
}

// Maj(x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z)
function maj64(x, y, z) {
	return [
		((x[0] & y[0]) ^ (x[0] & z[0]) ^ (y[0] & z[0])) & 0xFFFFFFFF,
		((x[1] & y[1]) ^ (x[1] & z[1]) ^ (y[1] & z[1])) & 0xFFFFFFFF
	];
}

// Sigma0(x) = ROTR(28, x) XOR ROTR(34, x) XOR ROTR(39, x)
function sigma0_64(x) {
	return xor64_3(rotr64(x, 28), rotr64(x, 34), rotr64(x, 39));
}

// Sigma1(x) = ROTR(14, x) XOR ROTR(18, x) XOR ROTR(41, x)
function sigma1_64(x) {
	return xor64_3(rotr64(x, 14), rotr64(x, 18), rotr64(x, 41));
}

// sigma0(x) = ROTR(1, x) XOR ROTR(8, x) XOR SHR(7, x)
function lsigma0_64(x) {
	return xor64_3(rotr64(x, 1), rotr64(x, 8), shr64(x, 7));
}

// sigma1(x) = ROTR(19, x) XOR ROTR(61, x) XOR SHR(6, x)
function lsigma1_64(x) {
	return xor64_3(rotr64(x, 19), rotr64(x, 61), shr64(x, 6));
}

// ---------- Precomputed SHA-512 round constants K (80 entries) ----------
// Each as [high32, low32]
const K = [
	[0x428a2f98, 0xd728ae22], [0x71374491, 0x23ef65cd], [0xb5c0fbcf, 0xec4d3b2f], [0xe9b5dba5, 0x8189dbbc],
	[0x3956c25b, 0xf348b538], [0x59f111f1, 0xb605d019], [0x923f82a4, 0xaf194f9b], [0xab1c5ed5, 0xda6d8118],
	[0xd807aa98, 0xa3030242], [0x12835b01, 0x45706fbe], [0x243185be, 0x4ee4b28c], [0x550c7dc3, 0xd5ffb4e2],
	[0x72be5d74, 0xf27b896f], [0x80deb1fe, 0x3b1696b1], [0x9bdc06a7, 0x25c71235], [0xc19bf174, 0xcf692694],
	[0xe49b69c1, 0x9ef14ad2], [0xefbe4786, 0x384f25e3], [0x0fc19dc6, 0x8b8cd5b5], [0x240ca1cc, 0x77ac9c65],
	[0x2de92c6f, 0x592b0275], [0x4a7484aa, 0x6ea6e483], [0x5cb0a9dc, 0xbd41fbd4], [0x76f988da, 0x831153b5],
	[0x983e5152, 0xee66dfab], [0xa831c66d, 0x2db43210], [0xb00327c8, 0x98fb213f], [0xbf597fc7, 0xbeef0ee4],
	[0xc6e00bf3, 0x3da88fc2], [0xd5a79147, 0x930aa725], [0x06ca6351, 0xe003826f], [0x14292967, 0x0a0e6e70],
	[0x27b70a85, 0x46d22ffc], [0x2e1b2138, 0x5c26c926], [0x4d2c6dfc, 0x5ac42aed], [0x53380d13, 0x9d95b3df],
	[0x650a7354, 0x8baf63de], [0x766a0abb, 0x3c77b2a8], [0x81c2c92e, 0x47edaee6], [0x92722c85, 0x1482353b],
	[0xa2bfe8a1, 0x4cf10364], [0xa81a664b, 0xbc423001], [0xc24b8b70, 0xd0f89791], [0xc76c51a3, 0x0654be30],
	[0xd192e819, 0xd6ef5218], [0xd6990624, 0x5565a910], [0xf40e3585, 0x5771202a], [0x106aa070, 0x32bbd1b8],
	[0x19a4c116, 0xb8d2d0c8], [0x1e376c08, 0x5141ab53], [0x2748774c, 0xdf8eeb99], [0x34b0bcb5, 0xe19b48a8],
	[0x391c0cb3, 0xc5c95a63], [0x4ed8aa4a, 0xe3418acb], [0x5b9cca4f, 0x7763e373], [0x682e6ff3, 0xd6b2b8a3],
	[0x748f82ee, 0x5defb2fc], [0x78a5636f, 0x43172f60], [0x84c87814, 0xa1f0ab72], [0x8cc70208, 0x1a6439ec],
	[0x90befffa, 0x23631e28], [0xa4506ceb, 0xde82bde9], [0xbef9a3f7, 0xb2c67915], [0xc67178f2, 0xe372532b],
	[0xca273ece, 0xea26619c], [0xd186b8c7, 0x21c0c207], [0xeada7dd6, 0xcde0eb1e], [0xf57d4f7f, 0xee6ed178],
	[0x06f067aa, 0x72176fba], [0x0a637dc5, 0xa2c898a6], [0x113f9804, 0xbef90dae], [0x1b710b35, 0x131c471b],
	[0x28db77f5, 0x23047d84], [0x32caab7b, 0x40c72493], [0x3c9ebe0a, 0x15c9bebc], [0x431d67c4, 0x9c100d4c],
	[0x4cc5d4be, 0xcb3e42b6], [0x597f299c, 0xfc657e2a], [0x5fcb6fab, 0x3ad6faec], [0x6c44198c, 0x4a475817]
];

// ---------- Initial hash values H0 ----------
const H0 = [
	[0x6a09e667, 0xf3bcc908],
	[0xbb67ae85, 0x84caa73b],
	[0x3c6ef372, 0xfe94f82b],
	[0xa54ff53a, 0x5f1d36f1],
	[0x510e527f, 0xade682d1],
	[0x9b05688c, 0x2b3e6c1f],
	[0x1f83d9ab, 0xfb41bd6b],
	[0x5be0cd19, 0x137e2179]
];

// ---------- 64-bit word to 16-bit little-endian array helper ----------

// Append four 16-bit values (little-endian order) from a [high32, low32] pair into arr
// Big-endian bytes of the 64-bit word: B0 B1 B2 B3 B4 B5 B6 B7
// Little-endian 16-bit: [B1<<8|B0, B3<<8|B2, B5<<8|B4, B7<<8|B6]
function push_word64_le16(arr, pair) {
	const hi = pair[0] & 0xFFFFFFFF;
	const lo = pair[1] & 0xFFFFFFFF;
	push(arr, ((shr32(hi, 16) & 0xFF) << 8) | (shr32(hi, 24) & 0xFF));
	push(arr, ((hi & 0xFF) << 8) | (shr32(hi, 8) & 0xFF));
	push(arr, ((shr32(lo, 16) & 0xFF) << 8) | (shr32(lo, 24) & 0xFF));
	push(arr, ((lo & 0xFF) << 8) | (shr32(lo, 8) & 0xFF));
}

// ---------- Message padding and parsing ----------

// Convert a byte array to an array of 64-bit words (big-endian)
function bytes_to_words64(bytes) {
	let words = [];
	const n = length(bytes);
	for (let i = 0; i < n; i += 8) {
		const hi = ((bytes[i]   & 0xFF) << 24) |
		           ((bytes[i+1] & 0xFF) << 16) |
		           ((bytes[i+2] & 0xFF) << 8)  |
		            (bytes[i+3] & 0xFF);
		const lo = ((bytes[i+4] & 0xFF) << 24) |
		           ((bytes[i+5] & 0xFF) << 16) |
		           ((bytes[i+6] & 0xFF) << 8)  |
		            (bytes[i+7] & 0xFF);
		push(words, [hi & 0xFFFFFFFF, lo & 0xFFFFFFFF]);
	}
	return words;
}

// Pad the message bytes per SHA-512 spec
function pad_message(msg_bytes) {
	const msg_len = length(msg_bytes);
	const bit_len = msg_len * 8;

	// Append 0x80 byte
	push(msg_bytes, 0x80);

	// Pad with zeros until length ≡ 112 (mod 128)
	while ((length(msg_bytes) % 128) != 112) {
		push(msg_bytes, 0x00);
	}

	// Append 128-bit big-endian length (we only support up to ~2^53 bit messages,
	// so the upper 64 bits of the 128-bit length are zero)
	// Upper 64 bits (all zero for messages < 2^53 bits)
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);
	push(msg_bytes, 0x00);

	// Lower 64 bits of the bit length (big-endian)
	// bit_len can be up to ~2^53, so we need to split it into two 32-bit parts
	const bit_len_hi = (bit_len - (bit_len & 0xFFFFFFFF)) / 4294967296;
	const bit_len_lo = bit_len & 0xFFFFFFFF;

	push(msg_bytes, shr32(bit_len_hi, 24) & 0xFF);
	push(msg_bytes, shr32(bit_len_hi, 16) & 0xFF);
	push(msg_bytes, shr32(bit_len_hi, 8) & 0xFF);
	push(msg_bytes, bit_len_hi & 0xFF);
	push(msg_bytes, shr32(bit_len_lo, 24) & 0xFF);
	push(msg_bytes, shr32(bit_len_lo, 16) & 0xFF);
	push(msg_bytes, shr32(bit_len_lo, 8) & 0xFF);
	push(msg_bytes, bit_len_lo & 0xFF);

	return msg_bytes;
}

// ---------- Main SHA-512 function ----------

export function sha512trunc(input) {
	let msg_bytes = struct.unpack(`${length(input)}B`, input) ?? [];

	const padded = pad_message(msg_bytes);
	const num_blocks = length(padded) / 128;

	// Initialize hash values
	let h0 = [H0[0][0], H0[0][1]];
	let h1 = [H0[1][0], H0[1][1]];
	let h2 = [H0[2][0], H0[2][1]];
	let h3 = [H0[3][0], H0[3][1]];
	let h4 = [H0[4][0], H0[4][1]];
	let h5 = [H0[5][0], H0[5][1]];
	let h6 = [H0[6][0], H0[6][1]];
	let h7 = [H0[7][0], H0[7][1]];

	for (let blk = 0; blk < num_blocks; blk++) {
		// Extract 128-byte block and convert to 16 64-bit words
		const block_start = blk * 128;
		let block_bytes = [];
		for (let bi = 0; bi < 128; bi++) {
			push(block_bytes, padded[block_start + bi]);
		}
		const M = bytes_to_words64(block_bytes);

		// Prepare message schedule W[0..79]
		let W = [];
		// W[0..15] = M[0..15]
		for (let t = 0; t < 16; t++) {
			push(W, [M[t][0], M[t][1]]);
		}
		// W[16..79]
		for (let t = 16; t < 80; t++) {
			const s0 = lsigma0_64(W[t - 15]);
			const s1 = lsigma1_64(W[t - 2]);
			// W[t] = W[t-16] + s0 + W[t-7] + s1
			let wt = add64(W[t - 16], s0);
			wt = add64(wt, W[t - 7]);
			wt = add64(wt, s1);
			push(W, wt);
		}

		// Working variables
		let a = [h0[0], h0[1]];
		let b = [h1[0], h1[1]];
		let c = [h2[0], h2[1]];
		let d = [h3[0], h3[1]];
		let e = [h4[0], h4[1]];
		let f = [h5[0], h5[1]];
		let g = [h6[0], h6[1]];
		let h = [h7[0], h7[1]];

		// 80 rounds
		for (let t = 0; t < 80; t++) {
			// T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]
			const T1 = add64_5(h, sigma1_64(e), ch64(e, f, g), K[t], W[t]);
			// T2 = Sigma0(a) + Maj(a,b,c)
			const T2 = add64(sigma0_64(a), maj64(a, b, c));

			h = [g[0], g[1]];
			g = [f[0], f[1]];
			f = [e[0], e[1]];
			e = add64(d, T1);
			d = [c[0], c[1]];
			c = [b[0], b[1]];
			b = [a[0], a[1]];
			a = add64(T1, T2);
		}

		// Update hash values
		h0 = add64(h0, a);
		h1 = add64(h1, b);
		h2 = add64(h2, c);
		h3 = add64(h3, d);
		h4 = add64(h4, e);
		h5 = add64(h5, f);
		h6 = add64(h6, g);
		h7 = add64(h7, h);
	}

	// Produce final 512-bit digest as array of 64 bytes
	let digest = [];
	push_word64_le16(digest, h0);
	push_word64_le16(digest, h1);
	push_word64_le16(digest, h2);
	push_word64_le16(digest, h3);
	//push_word64_le16(digest, h4);
	//push_word64_le16(digest, h5);
	//push_word64_le16(digest, h6);
	//push_word64_le16(digest, h7);
	return digest;
};


// ---------- Hex helper for display ----------
const HEX_CHARS = "0123456789abcdef";

function u16le_to_hex(arr) {
	let s = "";
	for (let i = 0; i < length(arr); i++) {
		const v = arr[i] & 0xFFFF;
		// Print as little-endian bytes: low byte first, then high byte
		const lo = v & 0xFF;
		const hi = shr32(v, 8) & 0xFF;
		s += substr(HEX_CHARS, shr32(lo, 4) & 0xF, 1) + substr(HEX_CHARS, lo & 0xF, 1);
		s += substr(HEX_CHARS, shr32(hi, 4) & 0xF, 1) + substr(HEX_CHARS, hi & 0xF, 1);
	}
	return s;
}

/*

// ---------- Test ----------
// SHA-512("") = cf83e1357eefb8bd...
// SHA-512("abc") = ddaf35a193617aba...

print("SHA-512('')    = " + u16le_to_hex(sha512("")) + "\n");
print("SHA-512('abc') = " + u16le_to_hex(sha512("abc")) + "\n");
print("SHA-512('hello') = " + u16le_to_hex(sha512("hello")) + "\n");
*/
