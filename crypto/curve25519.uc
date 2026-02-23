// Copyright (c) 2007, 2013, 2014 Michele Bini
// [License text omitted for brevity]

import * as struct from "struct";
import * as sha512 from "sha512";

function c255lgetbit(n, c) {
  return (n[c >> 4] >> (c & 0xf)) & 1;
}
function c255lzero() {
  return [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
}
function c255lone() {
  return [1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
}
function c255lbase() {
  return [9,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
}

function c255lreduce(a) {
  let v = a[15];
  a[15] = v & 0x7fff;
  v = (0|(v / 0x8000)) * 19;
  a[0] = (v += a[0]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[1] = (v += a[1]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[2] = (v += a[2]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[3] = (v += a[3]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[4] = (v += a[4]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[5] = (v += a[5]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[6] = (v += a[6]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[7] = (v += a[7]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[8] = (v += a[8]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[9] = (v += a[9]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[10] = (v += a[10]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[11] = (v += a[11]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[12] = (v += a[12]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[13] = (v += a[13]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[14] = (v += a[14]) & 0xffff;
  v = (v >> 16) & 0xffff;
  a[15] += v;
}

function c255lsqr8h(a7, a6, a5, a4, a3, a2, a1, a0) {
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = a0*a0) & 0xffff;
  r[1] = (v = (0|(v / 0x10000)) + 2*a0*a1) & 0xffff;
  r[2] = (v = (0|(v / 0x10000)) + 2*a0*a2 + a1*a1) & 0xffff;
  r[3] = (v = (0|(v / 0x10000)) + 2*a0*a3 + 2*a1*a2) & 0xffff;
  r[4] = (v = (0|(v / 0x10000)) + 2*a0*a4 + 2*a1*a3 + a2*a2) & 0xffff;
  r[5] = (v = (0|(v / 0x10000)) + 2*a0*a5 + 2*a1*a4 + 2*a2*a3) & 0xffff;
  r[6] = (v = (0|(v / 0x10000)) + 2*a0*a6 + 2*a1*a5 + 2*a2*a4 + a3*a3) & 0xffff;
  r[7] = (v = (0|(v / 0x10000)) + 2*a0*a7 + 2*a1*a6 + 2*a2*a5 + 2*a3*a4) & 0xffff;
  r[8] = (v = (0|(v / 0x10000)) + 2*a1*a7 + 2*a2*a6 + 2*a3*a5 + a4*a4) & 0xffff;
  r[9] = (v = (0|(v / 0x10000)) + 2*a2*a7 + 2*a3*a6 + 2*a4*a5) & 0xffff;
  r[10] = (v = (0|(v / 0x10000)) + 2*a3*a7 + 2*a4*a6 + a5*a5) & 0xffff;
  r[11] = (v = (0|(v / 0x10000)) + 2*a4*a7 + 2*a5*a6) & 0xffff;
  r[12] = (v = (0|(v / 0x10000)) + 2*a5*a7 + a6*a6) & 0xffff;
  r[13] = (v = (0|(v / 0x10000)) + 2*a6*a7) & 0xffff;
  r[14] = (v = (0|(v / 0x10000)) + a7*a7) & 0xffff;
  r[15] = 0|(v / 0x10000);
  return r;
}

function c255lsqrmodp(a) {
  const x = c255lsqr8h(a[15], a[14], a[13], a[12], a[11], a[10], a[9], a[8]);
  const z = c255lsqr8h(a[7], a[6], a[5], a[4], a[3], a[2], a[1], a[0]);
  const y = c255lsqr8h(a[15] + a[7], a[14] + a[6], a[13] + a[5], a[12] + a[4], a[11] + a[3], a[10] + a[2], a[9] + a[1], a[8] + a[0]);
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = 0x800000 + z[0] + (y[8] -x[8] -z[8] + x[0] -0x80) * 38) & 0xffff;
  r[1] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[1] + (y[9] -x[9] -z[9] + x[1]) * 38) & 0xffff;
  r[2] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[2] + (y[10] -x[10] -z[10] + x[2]) * 38) & 0xffff;
  r[3] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[3] + (y[11] -x[11] -z[11] + x[3]) * 38) & 0xffff;
  r[4] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[4] + (y[12] -x[12] -z[12] + x[4]) * 38) & 0xffff;
  r[5] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[5] + (y[13] -x[13] -z[13] + x[5]) * 38) & 0xffff;
  r[6] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[6] + (y[14] -x[14] -z[14] + x[6]) * 38) & 0xffff;
  r[7] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[7] + (y[15] -x[15] -z[15] + x[7]) * 38) & 0xffff;
  r[8] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[8] + y[0] -x[0] -z[0] + x[8] * 38) & 0xffff;
  r[9] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[9] + y[1] -x[1] -z[1] + x[9] * 38) & 0xffff;
  r[10] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[10] + y[2] -x[2] -z[2] + x[10] * 38) & 0xffff;
  r[11] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[11] + y[3] -x[3] -z[3] + x[11] * 38) & 0xffff;
  r[12] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[12] + y[4] -x[4] -z[4] + x[12] * 38) & 0xffff;
  r[13] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[13] + y[5] -x[5] -z[5] + x[13] * 38) & 0xffff;
  r[14] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[14] + y[6] -x[6] -z[6] + x[14] * 38) & 0xffff;
  r[15] = 0x7fff80 + ((v >> 16) & 0xffff) + z[15] + y[7] -x[7] -z[7] + x[15] * 38;
  c255lreduce(r);
  return r;
}

function c255lmul8h(a7, a6, a5, a4, a3, a2, a1, a0, b7, b6, b5, b4, b3, b2, b1, b0) {
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = a0*b0) & 0xffff;
  r[1] = (v = (0|(v / 0x10000)) + a0*b1 + a1*b0) & 0xffff;
  r[2] = (v = (0|(v / 0x10000)) + a0*b2 + a1*b1 + a2*b0) & 0xffff;
  r[3] = (v = (0|(v / 0x10000)) + a0*b3 + a1*b2 + a2*b1 + a3*b0) & 0xffff;
  r[4] = (v = (0|(v / 0x10000)) + a0*b4 + a1*b3 + a2*b2 + a3*b1 + a4*b0) & 0xffff;
  r[5] = (v = (0|(v / 0x10000)) + a0*b5 + a1*b4 + a2*b3 + a3*b2 + a4*b1 + a5*b0) & 0xffff;
  r[6] = (v = (0|(v / 0x10000)) + a0*b6 + a1*b5 + a2*b4 + a3*b3 + a4*b2 + a5*b1 + a6*b0) & 0xffff;
  r[7] = (v = (0|(v / 0x10000)) + a0*b7 + a1*b6 + a2*b5 + a3*b4 + a4*b3 + a5*b2 + a6*b1 + a7*b0) & 0xffff;
  r[8] = (v = (0|(v / 0x10000)) + a1*b7 + a2*b6 + a3*b5 + a4*b4 + a5*b3 + a6*b2 + a7*b1) & 0xffff;
  r[9] = (v = (0|(v / 0x10000)) + a2*b7 + a3*b6 + a4*b5 + a5*b4 + a6*b3 + a7*b2) & 0xffff;
  r[10] = (v = (0|(v / 0x10000)) + a3*b7 + a4*b6 + a5*b5 + a6*b4 + a7*b3) & 0xffff;
  r[11] = (v = (0|(v / 0x10000)) + a4*b7 + a5*b6 + a6*b5 + a7*b4) & 0xffff;
  r[12] = (v = (0|(v / 0x10000)) + a5*b7 + a6*b6 + a7*b5) & 0xffff;
  r[13] = (v = (0|(v / 0x10000)) + a6*b7 + a7*b6) & 0xffff;
  r[14] = (v = (0|(v / 0x10000)) + a7*b7) & 0xffff;
  r[15] = (0|(v / 0x10000));
  return r;
}

function c255lmulmodp(a, b) {
  const x = c255lmul8h(a[15], a[14], a[13], a[12], a[11], a[10], a[9], a[8], b[15], b[14], b[13], b[12], b[11], b[10], b[9], b[8]);
  const z = c255lmul8h(a[7], a[6], a[5], a[4], a[3], a[2], a[1], a[0], b[7], b[6], b[5], b[4], b[3], b[2], b[1], b[0]);
  const y = c255lmul8h(a[15] + a[7], a[14] + a[6], a[13] + a[5], a[12] + a[4], a[11] + a[3], a[10] + a[2], a[9] + a[1], a[8] + a[0],
  			b[15] + b[7], b[14] + b[6], b[13] + b[5], b[12] + b[4], b[11] + b[3], b[10] + b[2], b[9] + b[1], b[8] + b[0]);
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = 0x800000 + z[0] + (y[8] -x[8] -z[8] + x[0] -0x80) * 38) & 0xffff;
  r[1] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[1] + (y[9] -x[9] -z[9] + x[1]) * 38) & 0xffff;
  r[2] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[2] + (y[10] -x[10] -z[10] + x[2]) * 38) & 0xffff;
  r[3] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[3] + (y[11] -x[11] -z[11] + x[3]) * 38) & 0xffff;
  r[4] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[4] + (y[12] -x[12] -z[12] + x[4]) * 38) & 0xffff;
  r[5] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[5] + (y[13] -x[13] -z[13] + x[5]) * 38) & 0xffff;
  r[6] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[6] + (y[14] -x[14] -z[14] + x[6]) * 38) & 0xffff;
  r[7] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[7] + (y[15] -x[15] -z[15] + x[7]) * 38) & 0xffff;
  r[8] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[8] + y[0] -x[0] -z[0] + x[8] * 38) & 0xffff;
  r[9] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[9] + y[1] -x[1] -z[1] + x[9] * 38) & 0xffff;
  r[10] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[10] + y[2] -x[2] -z[2] + x[10] * 38) & 0xffff;
  r[11] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[11] + y[3] -x[3] -z[3] + x[11] * 38) & 0xffff;
  r[12] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[12] + y[4] -x[4] -z[4] + x[12] * 38) & 0xffff;
  r[13] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[13] + y[5] -x[5] -z[5] + x[13] * 38) & 0xffff;
  r[14] = (v = 0x7fff80 + ((v >> 16) & 0xffff) + z[14] + y[6] -x[6] -z[6] + x[14] * 38) & 0xffff;
  r[15] = 0x7fff80 + ((v >> 16) & 0xffff) + z[15] + y[7] -x[7] -z[7] + x[15] * 38;
  c255lreduce(r);
  return r;
}

function c255laddmodp(a, b) {
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = ((((0|(a[15])) >> 15) & 0xffff) + (((0|(b[15])) >> 15) & 0xffff)) * 19 + a[0] + b[0]) & 0xffff;
  r[1] = (v = ((v >> 16) & 0xffff) + a[1] + b[1]) & 0xffff;
  r[2] = (v = ((v >> 16) & 0xffff) + a[2] + b[2]) & 0xffff;
  r[3] = (v = ((v >> 16) & 0xffff) + a[3] + b[3]) & 0xffff;
  r[4] = (v = ((v >> 16) & 0xffff) + a[4] + b[4]) & 0xffff;
  r[5] = (v = ((v >> 16) & 0xffff) + a[5] + b[5]) & 0xffff;
  r[6] = (v = ((v >> 16) & 0xffff) + a[6] + b[6]) & 0xffff;
  r[7] = (v = ((v >> 16) & 0xffff) + a[7] + b[7]) & 0xffff;
  r[8] = (v = ((v >> 16) & 0xffff) + a[8] + b[8]) & 0xffff;
  r[9] = (v = ((v >> 16) & 0xffff) + a[9] + b[9]) & 0xffff;
  r[10] = (v = ((v >> 16) & 0xffff) + a[10] + b[10]) & 0xffff;
  r[11] = (v = ((v >> 16) & 0xffff) + a[11] + b[11]) & 0xffff;
  r[12] = (v = ((v >> 16) & 0xffff) + a[12] + b[12]) & 0xffff;
  r[13] = (v = ((v >> 16) & 0xffff) + a[13] + b[13]) & 0xffff;
  r[14] = (v = ((v >> 16) & 0xffff) + a[14] + b[14]) & 0xffff;
  r[15] = ((v >> 16) & 0xffff) + (a[15] & 0x7fff) + (b[15] & 0x7fff);
  return r;
}

function c255lsubmodp(a, b) {
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = 0x80000 + ((((0|(a[15])) >> 15) & 0xffff) - (((0|(b[15])) >> 15) & 0xffff) - 1) * 19 + a[0] - b[0]) & 0xffff;
  r[1] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[1] - b[1]) & 0xffff;
  r[2] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[2] - b[2]) & 0xffff;
  r[3] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[3] - b[3]) & 0xffff;
  r[4] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[4] - b[4]) & 0xffff;
  r[5] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[5] - b[5]) & 0xffff;
  r[6] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[6] - b[6]) & 0xffff;
  r[7] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[7] - b[7]) & 0xffff;
  r[8] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[8] - b[8]) & 0xffff;
  r[9] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[9] - b[9]) & 0xffff;
  r[10] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[10] - b[10]) & 0xffff;
  r[11] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[11] - b[11]) & 0xffff;
  r[12] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[12] - b[12]) & 0xffff;
  r[13] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[13] - b[13]) & 0xffff;
  r[14] = (v = ((v >> 16) & 0xffff) + 0x7fff8 + a[14] - b[14]) & 0xffff;
  r[15] = ((v >> 16) & 0xffff) + 0x7ff8 + (a[15] & 0x7fff) - (b[15] & 0x7fff);
  return r;
}

/*
function _c255linvmodp(a) {
  const c = a;
  let i = 250;
  while (--i) {
    a = c255lsqrmodp(a);
    a = c255lmulmodp(a, c);
  }
  a = c255lsqrmodp(a);
  a = c255lsqrmodp(a); a = c255lmulmodp(a, c);
  a = c255lsqrmodp(a);
  a = c255lsqrmodp(a); a = c255lmulmodp(a, c);
  a = c255lsqrmodp(a); a = c255lmulmodp(a, c);
  return a;
};
*/

/**
 * Optimized modular inverse for Curve25519 field elements.
 *
 * Computes a^(p-2) mod p where p = 2^255 - 19, using Fermat's little theorem.
 * Uses Daniel J. Bernstein's addition chain from the original Curve25519 paper,
 * which requires only 254 squarings and 11 multiplications.
 *
 * The original naive implementation did ~249 square-multiply pairs (249 sqr + 249 mul),
 * plus a tail of 5 sqr + 3 mul = 254 sqr + 252 mul total.
 * This version: 254 sqr + 11 mul — saving ~241 multiplications.
 *
 * Addition chain for p - 2 = 2^255 - 21:
 *
 *   Build small powers:
 *     a^2       = sqr(a)
 *     a^9       = sqr(sqr(a^2)) * a  => 2 sqr + 1 mul from a^2
 *     a^11      = a^9 * a^2          => 1 mul
 *     a^(2^5-1) = sqr(a^11) * a^9   => 1 sqr + 1 mul  (a^31 = x5)
 *
 *   Doubling strategy to build long runs of 1-bits:
 *     x10  = sqr^5(x5)   * x5       =>  5 sqr + 1 mul  (a^(2^10 - 1))
 *     x20  = sqr^10(x10) * x10      => 10 sqr + 1 mul  (a^(2^20 - 1))
 *     x40  = sqr^20(x20) * x20      => 20 sqr + 1 mul  (a^(2^40 - 1))
 *     x50  = sqr^10(x40) * x10      => 10 sqr + 1 mul  (a^(2^50 - 1))
 *     x100 = sqr^50(x50) * x50      => 50 sqr + 1 mul  (a^(2^100 - 1))
 *
 *   Final assembly for 2^255 - 21:
 *     sqr^100(x100) * x100           => 100 sqr + 1 mul (a^(2^200 - 1))
 *     sqr^50(above)  * x50           =>  50 sqr + 1 mul (a^(2^250 - 1))
 *     sqr^5(above)   * a^11          =>   5 sqr + 1 mul (a^(2^255 - 21))
 *
 *   Totals: 254 squarings + 11 multiplications
 *
 * Reference: https://briansmith.org/ecc-inversion-addition-chains-01
 * Original: https://cr.yp.to/ecdh/curve25519-20060209.pdf
 */
function c255linvmodp(a) {
  // a^1
  const _1 = a;

  // a^2
  const _2 = c255lsqrmodp(_1);

  // a^9 = ((a^2)^2)^2 * a = a^8 * a
  let _9 = c255lsqrmodp(_2);       // a^4
  _9 = c255lsqrmodp(_9);            // a^8
  _9 = c255lmulmodp(_9, _1);        // a^9

  // a^11 = a^9 * a^2
  const _11 = c255lmulmodp(_9, _2); // a^11

  // x5 = a^(2^5 - 1) = a^31 = (a^11)^2 * a^9
  const x5 = c255lmulmodp(c255lsqrmodp(_11), _9); // a^22 * a^9 = a^31

  // x10 = a^(2^10 - 1) = (x5)^(2^5) * x5
  let x10 = x5;
  for (let i = 0; i < 5; i++) x10 = c255lsqrmodp(x10);
  x10 = c255lmulmodp(x10, x5);

  // x20 = a^(2^20 - 1) = (x10)^(2^10) * x10
  let x20 = x10;
  for (let i = 0; i < 10; i++) x20 = c255lsqrmodp(x20);
  x20 = c255lmulmodp(x20, x10);

  // x40 = a^(2^40 - 1) = (x20)^(2^20) * x20
  let x40 = x20;
  for (let i = 0; i < 20; i++) x40 = c255lsqrmodp(x40);
  x40 = c255lmulmodp(x40, x20);

  // x50 = a^(2^50 - 1) = (x40)^(2^10) * x10
  let x50 = x40;
  for (let i = 0; i < 10; i++) x50 = c255lsqrmodp(x50);
  x50 = c255lmulmodp(x50, x10);

  // x100 = a^(2^100 - 1) = (x50)^(2^50) * x50
  let x100 = x50;
  for (let i = 0; i < 50; i++) x100 = c255lsqrmodp(x100);
  x100 = c255lmulmodp(x100, x50);

  // t = a^(2^200 - 1) = (x100)^(2^100) * x100
  let t = x100;
  for (let i = 0; i < 100; i++) t = c255lsqrmodp(t);
  t = c255lmulmodp(t, x100);

  // t = a^(2^250 - 1) = t^(2^50) * x50
  for (let i = 0; i < 50; i++) t = c255lsqrmodp(t);
  t = c255lmulmodp(t, x50);

  // t = a^(2^255 - 32) ... then * a^11 = a^(2^255 - 21) = a^(p-2)
  for (let i = 0; i < 5; i++) t = c255lsqrmodp(t);
  t = c255lmulmodp(t, _11);

  return t;
}

function c255lmulasmall(a) {
  const m = 121665;
  const r = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  r[0] = (v = a[0] * m) & 0xffff;
  r[1] = (v = (0|(v / 0x10000)) + a[1]*m) & 0xffff;
  r[2] = (v = (0|(v / 0x10000)) + a[2]*m) & 0xffff;
  r[3] = (v = (0|(v / 0x10000)) + a[3]*m) & 0xffff;
  r[4] = (v = (0|(v / 0x10000)) + a[4]*m) & 0xffff;
  r[5] = (v = (0|(v / 0x10000)) + a[5]*m) & 0xffff;
  r[6] = (v = (0|(v / 0x10000)) + a[6]*m) & 0xffff;
  r[7] = (v = (0|(v / 0x10000)) + a[7]*m) & 0xffff;
  r[8] = (v = (0|(v / 0x10000)) + a[8]*m) & 0xffff;
  r[9] = (v = (0|(v / 0x10000)) + a[9]*m) & 0xffff;
  r[10] = (v = (0|(v / 0x10000)) + a[10]*m) & 0xffff;
  r[11] = (v = (0|(v / 0x10000)) + a[11]*m) & 0xffff;
  r[12] = (v = (0|(v / 0x10000)) + a[12]*m) & 0xffff;
  r[13] = (v = (0|(v / 0x10000)) + a[13]*m) & 0xffff;
  r[14] = (v = (0|(v / 0x10000)) + a[14]*m) & 0xffff;
  r[15] = (0|(v / 0x10000)) + a[15]*m;
  c255lreduce(r);
  return r;
}

function c255ldbl(x, z) {
  const m = c255lsqrmodp(c255laddmodp(x, z));
  const n = c255lsqrmodp(c255lsubmodp(x, z));
  const o = c255lsubmodp(m, n);
  const x_2 = c255lmulmodp(n, m);
  const z_2 = c255lmulmodp(c255laddmodp(c255lmulasmall(o), m), o);
  return [x_2, z_2];
}

function c255lsum(x, z, x_p, z_p, x_1) {
  const p = c255lmulmodp(c255lsubmodp(x, z), c255laddmodp(x_p, z_p));
  const q = c255lmulmodp(c255laddmodp(x, z), c255lsubmodp(x_p, z_p));
  const x_3 = c255lsqrmodp(c255laddmodp(p, q));
  const z_3 = c255lmulmodp(c255lsqrmodp(c255lsubmodp(p, q)), x_1);
  return [x_3, z_3];
}

// === Edwards to Montgomery conversion ===
// u = (1 + y) / (1 - y) mod p
function c255l_edwards_to_montgomery(y) {
  const one = c255lone();
  const num = c255laddmodp(one, y);    // 1 + y
  const den = c255lsubmodp(one, y);    // 1 - y
  const den_inv = c255linvmodp(den);   // (1 - y)^(-1)
  const u = c255lmulmodp(num, den_inv);
  c255lreduce(u);
  return u;
}

/*
// === Fully reduce to canonical form [0, p) ===
function c255lcanonical(a) {
  // Make a copy
  const r = slice(a);
  // First do a standard reduce
  c255lreduce(r);
  c255lreduce(r);
  // Now check if r >= p = 2^255 - 19
  // If so, subtract p
  // p in limbs: [0xffed, 0xffff, ..., 0xffff, 0x7fff]
  // Try subtracting p and see if we borrow
  const t = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
  let v;
  t[0] = (v = r[0] - 0xffed) & 0xffff;
  t[1] = (v = ((v >> 16) & 0xffff) + r[1] - 0xffff) & 0xffff;
  t[2] = (v = ((v >> 16) & 0xffff) + r[2] - 0xffff) & 0xffff;
  t[3] = (v = ((v >> 16) & 0xffff) + r[3] - 0xffff) & 0xffff;
  t[4] = (v = ((v >> 16) & 0xffff) + r[4] - 0xffff) & 0xffff;
  t[5] = (v = ((v >> 16) & 0xffff) + r[5] - 0xffff) & 0xffff;
  t[6] = (v = ((v >> 16) & 0xffff) + r[6] - 0xffff) & 0xffff;
  t[7] = (v = ((v >> 16) & 0xffff) + r[7] - 0xffff) & 0xffff;
  t[8] = (v = ((v >> 16) & 0xffff) + r[8] - 0xffff) & 0xffff;
  t[9] = (v = ((v >> 16) & 0xffff) + r[9] - 0xffff) & 0xffff;
  t[10] = (v = ((v >> 16) & 0xffff) + r[10] - 0xffff) & 0xffff;
  t[11] = (v = ((v >> 16) & 0xffff) + r[11] - 0xffff) & 0xffff;
  t[12] = (v = ((v >> 16) & 0xffff) + r[12] - 0xffff) & 0xffff;
  t[13] = (v = ((v >> 16) & 0xffff) + r[13] - 0xffff) & 0xffff;
  t[14] = (v = ((v >> 16) & 0xffff) + r[14] - 0xffff) & 0xffff;
  t[15] = ((v >> 16) & 0xffff) + r[15] - 0x7fff;
  // If t[15] >= 0 (no borrow), use t; otherwise use r
  const mask = (t[15] >> 15) & 1; // 1 if negative (borrow), 0 if ok
  for (let i = 0; i < 16; i++) {
    r[i] = mask ? r[i] : t[i];
  }
  return r;
}
*/

export function ed25519_pubkey_to_x25519(edkey) {
  return c255l_edwards_to_montgomery(edkey);
};

export function ed25519_privkey_to_x25519(edkey) {
  const xkey = sha512.sha512trunc(edkey); // 32 limbs = 512 bits
  // Clamp: clear bottom 3 bits, clear bit 255, set bit 254
  xkey[0] &= 0xFFF8;
  xkey[15] = (xkey[15] & 0x7FFF) | 0x4000;
  return xkey;
};

export function curve25519_raw(f, c) {
  const x_1 = c;
  let a = c255ldbl(x_1, c255lone());
  let q = [ slice(x_1), c255lone() ];

  // For correct constant-time operation, bit 255 should always be set to 1 so the following 'while' loop is never entered
  let n = 255;
  for (; !c255lgetbit(f, n); n--)
    ;
  if (n <= 0) {
    return c255lzero();
  }

  n--;
  for (; n >= 0; n--) {
    if (c255lgetbit(f, n)) {
      q = c255lsum(a[0], a[1], q[0], q[1], x_1);
      a = c255ldbl(a[0], a[1]);
    }
    else {
      a = c255lsum(a[0], a[1], q[0], q[1], x_1);
      q = c255ldbl(q[0], q[1]);
    }
  }

  q[1] = c255linvmodp(q[1]);
  q[0] = c255lmulmodp(q[0], q[1]);
  c255lreduce(q[0]);
  return q[0];
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
