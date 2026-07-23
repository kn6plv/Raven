// Copyright (c) 2007, 2013, 2014 Michele Bini
// [License text omitted for brevity]
//
// AI Notice:
// The original code was optimized and rewritten by Claude Fable 5 High
// in order to improve performance.
//
// Performance-optimized revision (ucode).
//
// The field arithmetic has been rewritten from the original radix-2^16
// (16 limbs, schoolbook/Karatsuba with per-limb carry chains) to the
// radix-2^25.5 representation used by ref10/curve25519-donna: 10 limbs of
// alternating 26/25 bits. ucode integers are 64-bit, so limb products and
// their sums (bounded ~2^63) are computed exactly with no carry handling
// inside the product loops — a field multiplication is 100 multiplies plus
// one 12-step carry chain, versus ~192 multiplies plus ~50 carry steps
// before, and additions/subtractions need no carries at all (10 ops each,
// versus ~90). This matters because ucode is interpreted: runtime is
// proportional to the number of VM operations executed.
//
// fe_mul/fe_sq were generated mechanically from the radix rule (coefficient
// 2 when both limb indices are odd, x19 on wraparound past limb 10) and
// match the ref10 reference formulas. The carry chain, freeze
// (canonicalization), and inversion addition chain (254 sq + 11 mul,
// Bernstein) are the standard ref10 constructions.
//
// Other changes:
//  - No allocation in the hot path: field ops write into caller-supplied
//    arrays; ladder state, step temporaries, and the inversion pool are
//    module-scope arrays allocated once. Outputs may alias inputs (every op
//    reads all inputs before writing).
//  - Bug fix: the scalar bit scan in curve25519_raw is bounded. The original
//    loops forever on an all-zero scalar (negative indices wrap around the
//    limb array, so a 1-bit is never found and its `n <= 0` check was
//    unreachable).
//  - Behavior change: results are now fully reduced (canonical) mod
//    2^255-19. The original could emit a non-canonical encoding in
//    degenerate cases (e.g. it returns p itself, not zero, for the
//    low-order input u=0). For all normal inputs the outputs are identical.
//
// Public API is unchanged: curve25519(f, c), curve25519_raw(f, c),
// ed25519_pubkey_to_x25519(edkey), ed25519_privkey_to_x25519(edkey).
// Keys remain 16-limb little-endian arrays of 16-bit values; conversion to
// and from the internal representation happens once per call at the
// boundaries.

import * as sha512 from 'sha512';

function c255lgetbit(n, c) {
  return (n[c >> 4] >> (c & 0xf)) & 1;
}
function c255lzero() {
  return [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
}
function c255lbase() {
  return [9,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
}

// ---------------------------------------------------------------------------
// Field element ops. An "fe" is 10 signed limbs, alternating 26/25 bits.
// fe_mul/fe_sq below are machine-generated from the radix rule and match the
// ref10 reference formulas.
// ---------------------------------------------------------------------------

function fe_mul(h, f, g) {
  const f0 = f[0], f1 = f[1], f2 = f[2], f3 = f[3], f4 = f[4], f5 = f[5], f6 = f[6], f7 = f[7], f8 = f[8], f9 = f[9];
  const g0 = g[0], g1 = g[1], g2 = g[2], g3 = g[3], g4 = g[4], g5 = g[5], g6 = g[6], g7 = g[7], g8 = g[8], g9 = g[9];
  const g1_19 = 19 * g1, g2_19 = 19 * g2, g3_19 = 19 * g3, g4_19 = 19 * g4, g5_19 = 19 * g5, g6_19 = 19 * g6, g7_19 = 19 * g7, g8_19 = 19 * g8, g9_19 = 19 * g9;
  const f1_2 = 2 * f1, f3_2 = 2 * f3, f5_2 = 2 * f5, f7_2 = 2 * f7, f9_2 = 2 * f9;
  let h0 = f0*g0 + f1_2*g9_19 + f2*g8_19 + f3_2*g7_19 + f4*g6_19 + f5_2*g5_19 + f6*g4_19 + f7_2*g3_19 + f8*g2_19 + f9_2*g1_19;
  let h1 = f0*g1 + f1*g0 + f2*g9_19 + f3*g8_19 + f4*g7_19 + f5*g6_19 + f6*g5_19 + f7*g4_19 + f8*g3_19 + f9*g2_19;
  let h2 = f0*g2 + f1_2*g1 + f2*g0 + f3_2*g9_19 + f4*g8_19 + f5_2*g7_19 + f6*g6_19 + f7_2*g5_19 + f8*g4_19 + f9_2*g3_19;
  let h3 = f0*g3 + f1*g2 + f2*g1 + f3*g0 + f4*g9_19 + f5*g8_19 + f6*g7_19 + f7*g6_19 + f8*g5_19 + f9*g4_19;
  let h4 = f0*g4 + f1_2*g3 + f2*g2 + f3_2*g1 + f4*g0 + f5_2*g9_19 + f6*g8_19 + f7_2*g7_19 + f8*g6_19 + f9_2*g5_19;
  let h5 = f0*g5 + f1*g4 + f2*g3 + f3*g2 + f4*g1 + f5*g0 + f6*g9_19 + f7*g8_19 + f8*g7_19 + f9*g6_19;
  let h6 = f0*g6 + f1_2*g5 + f2*g4 + f3_2*g3 + f4*g2 + f5_2*g1 + f6*g0 + f7_2*g9_19 + f8*g8_19 + f9_2*g7_19;
  let h7 = f0*g7 + f1*g6 + f2*g5 + f3*g4 + f4*g3 + f5*g2 + f6*g1 + f7*g0 + f8*g9_19 + f9*g8_19;
  let h8 = f0*g8 + f1_2*g7 + f2*g6 + f3_2*g5 + f4*g4 + f5_2*g3 + f6*g2 + f7_2*g1 + f8*g0 + f9_2*g9_19;
  let h9 = f0*g9 + f1*g8 + f2*g7 + f3*g6 + f4*g5 + f5*g4 + f6*g3 + f7*g2 + f8*g1 + f9*g0;

  let c;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h1 + 0x1000000) >> 25; h2 += c; h1 -= c << 25;
  c = (h5 + 0x1000000) >> 25; h6 += c; h5 -= c << 25;
  c = (h2 + 0x2000000) >> 26; h3 += c; h2 -= c << 26;
  c = (h6 + 0x2000000) >> 26; h7 += c; h6 -= c << 26;
  c = (h3 + 0x1000000) >> 25; h4 += c; h3 -= c << 25;
  c = (h7 + 0x1000000) >> 25; h8 += c; h7 -= c << 25;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h8 + 0x2000000) >> 26; h9 += c; h8 -= c << 26;
  c = (h9 + 0x1000000) >> 25; h0 += c * 19; h9 -= c << 25;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  h[0] = h0; h[1] = h1; h[2] = h2; h[3] = h3; h[4] = h4;
  h[5] = h5; h[6] = h6; h[7] = h7; h[8] = h8; h[9] = h9;
}

function fe_sq(h, f) {
  const f0 = f[0], f1 = f[1], f2 = f[2], f3 = f[3], f4 = f[4], f5 = f[5], f6 = f[6], f7 = f[7], f8 = f[8], f9 = f[9];
  let h0 = f0*f0 + 76*f1*f9 + 38*f2*f8 + 76*f3*f7 + 38*f4*f6 + 38*f5*f5;
  let h1 = 2*f0*f1 + 38*f2*f9 + 38*f3*f8 + 38*f4*f7 + 38*f5*f6;
  let h2 = 2*f0*f2 + 2*f1*f1 + 76*f3*f9 + 38*f4*f8 + 76*f5*f7 + 19*f6*f6;
  let h3 = 2*f0*f3 + 2*f1*f2 + 38*f4*f9 + 38*f5*f8 + 38*f6*f7;
  let h4 = 2*f0*f4 + 4*f1*f3 + f2*f2 + 76*f5*f9 + 38*f6*f8 + 38*f7*f7;
  let h5 = 2*f0*f5 + 2*f1*f4 + 2*f2*f3 + 38*f6*f9 + 38*f7*f8;
  let h6 = 2*f0*f6 + 4*f1*f5 + 2*f2*f4 + 2*f3*f3 + 76*f7*f9 + 19*f8*f8;
  let h7 = 2*f0*f7 + 2*f1*f6 + 2*f2*f5 + 2*f3*f4 + 38*f8*f9;
  let h8 = 2*f0*f8 + 4*f1*f7 + 2*f2*f6 + 4*f3*f5 + f4*f4 + 38*f9*f9;
  let h9 = 2*f0*f9 + 2*f1*f8 + 2*f2*f7 + 2*f3*f6 + 2*f4*f5;

  let c;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h1 + 0x1000000) >> 25; h2 += c; h1 -= c << 25;
  c = (h5 + 0x1000000) >> 25; h6 += c; h5 -= c << 25;
  c = (h2 + 0x2000000) >> 26; h3 += c; h2 -= c << 26;
  c = (h6 + 0x2000000) >> 26; h7 += c; h6 -= c << 26;
  c = (h3 + 0x1000000) >> 25; h4 += c; h3 -= c << 25;
  c = (h7 + 0x1000000) >> 25; h8 += c; h7 -= c << 25;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h8 + 0x2000000) >> 26; h9 += c; h8 -= c << 26;
  c = (h9 + 0x1000000) >> 25; h0 += c * 19; h9 -= c << 25;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  h[0] = h0; h[1] = h1; h[2] = h2; h[3] = h3; h[4] = h4;
  h[5] = h5; h[6] = h6; h[7] = h7; h[8] = h8; h[9] = h9;
}

function fe_copy(h, f) {
  for (let i = 0; i < 10; i++)
    h[i] = f[i];
}

// No carries needed: limbs are signed and the slack absorbs one add/sub
// between multiplications (the only pattern the ladder uses).
function fe_add(h, f, g) {
  h[0] = f[0] + g[0]; h[1] = f[1] + g[1]; h[2] = f[2] + g[2]; h[3] = f[3] + g[3]; h[4] = f[4] + g[4];
  h[5] = f[5] + g[5]; h[6] = f[6] + g[6]; h[7] = f[7] + g[7]; h[8] = f[8] + g[8]; h[9] = f[9] + g[9];
}

function fe_sub(h, f, g) {
  h[0] = f[0] - g[0]; h[1] = f[1] - g[1]; h[2] = f[2] - g[2]; h[3] = f[3] - g[3]; h[4] = f[4] - g[4];
  h[5] = f[5] - g[5]; h[6] = f[6] - g[6]; h[7] = f[7] - g[7]; h[8] = f[8] - g[8]; h[9] = f[9] - g[9];
}

// h = f * 121665 (the curve constant (A-2)/4), with the standard carry chain.
function fe_mul_small(h, f) {
  let h0 = f[0] * 121665, h1 = f[1] * 121665, h2 = f[2] * 121665, h3 = f[3] * 121665, h4 = f[4] * 121665;
  let h5 = f[5] * 121665, h6 = f[6] * 121665, h7 = f[7] * 121665, h8 = f[8] * 121665, h9 = f[9] * 121665;
  let c;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h1 + 0x1000000) >> 25; h2 += c; h1 -= c << 25;
  c = (h5 + 0x1000000) >> 25; h6 += c; h5 -= c << 25;
  c = (h2 + 0x2000000) >> 26; h3 += c; h2 -= c << 26;
  c = (h6 + 0x2000000) >> 26; h7 += c; h6 -= c << 26;
  c = (h3 + 0x1000000) >> 25; h4 += c; h3 -= c << 25;
  c = (h7 + 0x1000000) >> 25; h8 += c; h7 -= c << 25;
  c = (h4 + 0x2000000) >> 26; h5 += c; h4 -= c << 26;
  c = (h8 + 0x2000000) >> 26; h9 += c; h8 -= c << 26;
  c = (h9 + 0x1000000) >> 25; h0 += c * 19; h9 -= c << 25;
  c = (h0 + 0x2000000) >> 26; h1 += c; h0 -= c << 26;
  h[0] = h0; h[1] = h1; h[2] = h2; h[3] = h3; h[4] = h4;
  h[5] = h5; h[6] = h6; h[7] = h7; h[8] = h8; h[9] = h9;
}

// ---------------------------------------------------------------------------
// Conversion between the public 16x16-bit limb format and the internal fe.
// Runs once per call at the API boundary.
// ---------------------------------------------------------------------------
const FE_START = [0, 26, 51, 77, 102, 128, 153, 179, 204, 230];
const FE_WIDTH = [26, 25, 26, 25, 26, 25, 26, 25, 26, 25];

function fe_from16(h, l) {
  for (let i = 0; i < 10; i++) {
    let start = FE_START[i];
    let j = start >> 4;
    let sh = start & 15;
    let acc = l[j] >> sh;
    let taken = 16 - sh;
    while (taken < FE_WIDTH[i]) {
      j++;
      acc |= l[j] << taken;
      taken += 16;
    }
    h[i] = acc & ((1 << FE_WIDTH[i]) - 1);
  }
  // Bit 255 contributes 2^255 = 19 mod p (matches the original code's
  // top-bit folding in its add/sub/reduce routines).
  h[0] += 19 * ((l[15] >> 15) & 1);
}

// Canonicalize (ref10 fe_tobytes "freeze") and pack into 16x16-bit limbs.
function fe_to16(f) {
  let h0 = f[0], h1 = f[1], h2 = f[2], h3 = f[3], h4 = f[4];
  let h5 = f[5], h6 = f[6], h7 = f[7], h8 = f[8], h9 = f[9];

  let q = (19 * h9 + 0x1000000) >> 25;
  q = (h0 + q) >> 26;
  q = (h1 + q) >> 25;
  q = (h2 + q) >> 26;
  q = (h3 + q) >> 25;
  q = (h4 + q) >> 26;
  q = (h5 + q) >> 25;
  q = (h6 + q) >> 26;
  q = (h7 + q) >> 25;
  q = (h8 + q) >> 26;
  q = (h9 + q) >> 25;

  h0 += 19 * q;
  let c;
  c = h0 >> 26; h1 += c; h0 -= c << 26;
  c = h1 >> 25; h2 += c; h1 -= c << 25;
  c = h2 >> 26; h3 += c; h2 -= c << 26;
  c = h3 >> 25; h4 += c; h3 -= c << 25;
  c = h4 >> 26; h5 += c; h4 -= c << 26;
  c = h5 >> 25; h6 += c; h5 -= c << 25;
  c = h6 >> 26; h7 += c; h6 -= c << 26;
  c = h7 >> 25; h8 += c; h7 -= c << 25;
  c = h8 >> 26; h9 += c; h8 -= c << 26;
  h9 -= (h9 >> 25) << 25;

  const limbs = [h0, h1, h2, h3, h4, h5, h6, h7, h8, h9];
  let out = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
  for (let i = 0; i < 10; i++) {
    let j = FE_START[i] >> 4;
    let x = limbs[i] << (FE_START[i] & 15);
    out[j] |= x & 0xffff;
    x >>= 16;
    while (x) {
      j++;
      out[j] |= x & 0xffff;
      x >>= 16;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Inversion: Bernstein's addition chain, 254 sq + 11 mul. r may alias a.
// All intermediates live in a fixed pool.
// ---------------------------------------------------------------------------
const i_2 = [0,0,0,0,0, 0,0,0,0,0];
const i_9 = [0,0,0,0,0, 0,0,0,0,0];
const i_11 = [0,0,0,0,0, 0,0,0,0,0];
const iX5 = [0,0,0,0,0, 0,0,0,0,0];
const iX10 = [0,0,0,0,0, 0,0,0,0,0];
const iX20 = [0,0,0,0,0, 0,0,0,0,0];
const iX40 = [0,0,0,0,0, 0,0,0,0,0];
const iX50 = [0,0,0,0,0, 0,0,0,0,0];
const iX100 = [0,0,0,0,0, 0,0,0,0,0];
const iT = [0,0,0,0,0, 0,0,0,0,0];

function fe_invert(r, a) {
  fe_sq(i_2, a);                     // a^2
  fe_sq(i_9, i_2);                   // a^4
  fe_sq(i_9, i_9);                   // a^8
  fe_mul(i_9, i_9, a);               // a^9
  fe_mul(i_11, i_9, i_2);            // a^11
  fe_sq(iX5, i_11);                  // a^22
  fe_mul(iX5, iX5, i_9);             // x5 = a^31 = a^(2^5-1)

  fe_copy(iX10, iX5);
  for (let i = 0; i < 5; i++) fe_sq(iX10, iX10);
  fe_mul(iX10, iX10, iX5);           // x10 = a^(2^10-1)

  fe_copy(iX20, iX10);
  for (let i = 0; i < 10; i++) fe_sq(iX20, iX20);
  fe_mul(iX20, iX20, iX10);          // x20 = a^(2^20-1)

  fe_copy(iX40, iX20);
  for (let i = 0; i < 20; i++) fe_sq(iX40, iX40);
  fe_mul(iX40, iX40, iX20);          // x40 = a^(2^40-1)

  fe_copy(iX50, iX40);
  for (let i = 0; i < 10; i++) fe_sq(iX50, iX50);
  fe_mul(iX50, iX50, iX10);          // x50 = a^(2^50-1)

  fe_copy(iX100, iX50);
  for (let i = 0; i < 50; i++) fe_sq(iX100, iX100);
  fe_mul(iX100, iX100, iX50);        // x100 = a^(2^100-1)

  fe_copy(iT, iX100);
  for (let i = 0; i < 100; i++) fe_sq(iT, iT);
  fe_mul(iT, iT, iX100);             // a^(2^200-1)

  for (let i = 0; i < 50; i++) fe_sq(iT, iT);
  fe_mul(iT, iT, iX50);              // a^(2^250-1)

  for (let i = 0; i < 5; i++) fe_sq(iT, iT);
  fe_mul(r, iT, i_11);               // a^(2^255-21) = a^(p-2)
}

// ---------------------------------------------------------------------------
// Ladder steps. Output fe's may alias inputs (temps isolate reads/writes).
// ---------------------------------------------------------------------------
const dT1 = [0,0,0,0,0, 0,0,0,0,0];
const dT2 = [0,0,0,0,0, 0,0,0,0,0];
const dT3 = [0,0,0,0,0, 0,0,0,0,0];
const dT4 = [0,0,0,0,0, 0,0,0,0,0];

function mont_dbl(ox, oz, x, z) {
  fe_add(dT1, x, z);
  fe_sub(dT2, x, z);
  fe_sq(dT1, dT1);            // m = (x+z)^2
  fe_sq(dT2, dT2);            // n = (x-z)^2
  fe_sub(dT3, dT1, dT2);      // o = m - n
  fe_mul(ox, dT2, dT1);       // x2 = n * m
  fe_mul_small(dT4, dT3);     // 121665 * o
  fe_add(dT4, dT4, dT1);      // 121665*o + m
  fe_mul(oz, dT4, dT3);       // z2 = (121665*o + m) * o
}

function mont_sum(ox, oz, x, z, x_p, z_p, x_1) {
  fe_sub(dT1, x, z);
  fe_add(dT2, x_p, z_p);
  fe_mul(dT1, dT1, dT2);      // p = (x - z) * (xp + zp)
  fe_add(dT3, x, z);
  fe_sub(dT4, x_p, z_p);
  fe_mul(dT3, dT3, dT4);      // q = (x + z) * (xp - zp)
  fe_add(dT2, dT1, dT3);      // p + q
  fe_sub(dT4, dT1, dT3);      // p - q
  fe_sq(ox, dT2);             // x3 = (p+q)^2
  fe_sq(dT4, dT4);            // (p-q)^2
  fe_mul(oz, dT4, x_1);       // z3 = (p-q)^2 * x1
}

// ---------------------------------------------------------------------------
// Edwards -> Montgomery conversion: u = (1 + y) / (1 - y) mod p
// ---------------------------------------------------------------------------
const eY = [0,0,0,0,0, 0,0,0,0,0];
const eNum = [0,0,0,0,0, 0,0,0,0,0];
const eDen = [0,0,0,0,0, 0,0,0,0,0];
const eOne = [1,0,0,0,0, 0,0,0,0,0];

function edwards_to_montgomery(y) {
  fe_from16(eY, y);
  fe_add(eNum, eOne, eY);     // 1 + y
  fe_sub(eDen, eOne, eY);     // 1 - y
  fe_invert(eDen, eDen);      // (1 - y)^(-1)
  fe_mul(eNum, eNum, eDen);
  return fe_to16(eNum);
}

export function ed25519_pubkey_to_x25519(edkey) {
  return edwards_to_montgomery(edkey);
};

export function ed25519_privkey_to_x25519(edkey) {
  const xkey = sha512.sha512trunc(edkey); // 32 limbs = 512 bits
  // Clamp: clear bottom 3 bits, clear bit 255, set bit 254
  xkey[0] &= 0xFFF8;
  xkey[15] = (xkey[15] & 0x7FFF) | 0x4000;
  return xkey;
};

// ---------------------------------------------------------------------------
// Montgomery ladder (same bit-scan and step order as the original)
// ---------------------------------------------------------------------------
const lX1 = [0,0,0,0,0, 0,0,0,0,0];
const lAx = [0,0,0,0,0, 0,0,0,0,0];
const lAz = [0,0,0,0,0, 0,0,0,0,0];
const lQx = [0,0,0,0,0, 0,0,0,0,0];
const lQz = [0,0,0,0,0, 0,0,0,0,0];

export function curve25519_raw(f, c) {
  fe_from16(lX1, c);

  // a = dbl(x1, 1); q = (x1, 1)
  for (let i = 1; i < 10; i++) lAz[i] = 0;
  lAz[0] = 1;
  mont_dbl(lAx, lAz, lX1, lAz);
  fe_copy(lQx, lX1);
  for (let i = 1; i < 10; i++) lQz[i] = 0;
  lQz[0] = 1;

  // For correct constant-time operation, bit 255 should always be set to 1 so the following loop is never entered.
  // (Bug fix vs original: bounded scan — the original loops forever on an
  // all-zero scalar, since negative bit indices wrap around the limb array
  // and never read a 1-bit, making the `n <= 0` check below unreachable.)
  let n = 255;
  for (; n > 0 && !c255lgetbit(f, n); n--)
    ;
  if (n <= 0) {
    return c255lzero();
  }

  n--;
  for (; n >= 0; n--) {
    if (c255lgetbit(f, n)) {
      mont_sum(lQx, lQz, lAx, lAz, lQx, lQz, lX1);
      mont_dbl(lAx, lAz, lAx, lAz);
    }
    else {
      mont_sum(lAx, lAz, lAx, lAz, lQx, lQz, lX1);
      mont_dbl(lQx, lQz, lQx, lQz);
    }
  }

  fe_invert(lQz, lQz);
  fe_mul(lQx, lQx, lQz);
  return fe_to16(lQx);
};

export function curve25519(f, c) {
    if (!c) {
      c = c255lbase();
    }
    f[0] &= 0xFFF8;
    f[15] = (f[15] & 0x7FFF) | 0x4000;
    c[15] &= 0x7FFF;
    return curve25519_raw(f, c);
};
