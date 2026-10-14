// Hearth phone pages: seals what the phone sends with ChaCha20-Poly1305 (RFC 8439), under a key that came in the
// page link's #fragment, which the browser never sends over the network. A page served over plain http on the home
// network can't use the browser's own crypto (WebCrypto needs https), so this is a small implementation of its own;
// the TV opens it with Android's. Needs BigInt (Chrome 67, Safari 14).
var HearthSeal = (function () {
  function rotl(a, b) { return (a << b) | (a >>> (32 - b)); }
  function le32(b, i) { return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24); }
  function qr(s, a, b, c, d) {
    s[a] = (s[a] + s[b]) | 0; s[d] = rotl(s[d] ^ s[a], 16);
    s[c] = (s[c] + s[d]) | 0; s[b] = rotl(s[b] ^ s[c], 12);
    s[a] = (s[a] + s[b]) | 0; s[d] = rotl(s[d] ^ s[a], 8);
    s[c] = (s[c] + s[d]) | 0; s[b] = rotl(s[b] ^ s[c], 7);
  }
  function block(key, counter, nonce) {
    var s = new Int32Array(16), i;
    s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574;
    for (i = 0; i < 8; i++) s[4 + i] = le32(key, 4 * i);
    s[12] = counter;
    for (i = 0; i < 3; i++) s[13 + i] = le32(nonce, 4 * i);
    var w = new Int32Array(s);
    for (i = 0; i < 10; i++) {
      qr(w, 0, 4, 8, 12); qr(w, 1, 5, 9, 13); qr(w, 2, 6, 10, 14); qr(w, 3, 7, 11, 15);
      qr(w, 0, 5, 10, 15); qr(w, 1, 6, 11, 12); qr(w, 2, 7, 8, 13); qr(w, 3, 4, 9, 14);
    }
    var out = new Uint8Array(64);
    for (i = 0; i < 16; i++) {
      var v = (w[i] + s[i]) | 0;
      out[4 * i] = v & 255; out[4 * i + 1] = (v >>> 8) & 255; out[4 * i + 2] = (v >>> 16) & 255; out[4 * i + 3] = (v >>> 24) & 255;
    }
    return out;
  }
  function chacha(key, counter, nonce, data) {
    var out = new Uint8Array(data.length);
    for (var j = 0; j < data.length; j += 64) {
      var ks = block(key, counter + j / 64, nonce);
      for (var k = 0; k < 64 && j + k < data.length; k++) out[j + k] = data[j + k] ^ ks[k];
    }
    return out;
  }
  function leBig(b) {
    var n = BigInt(0);
    for (var i = b.length - 1; i >= 0; i--) n = (n << BigInt(8)) | BigInt(b[i]);
    return n;
  }
  function poly1305(key, msg) {
    var r = leBig(key.subarray(0, 16)) & BigInt("0x0ffffffc0ffffffc0ffffffc0fffffff");
    var s = leBig(key.subarray(16, 32));
    var p = (BigInt(1) << BigInt(130)) - BigInt(5);
    var acc = BigInt(0);
    for (var i = 0; i < msg.length; i += 16) {
      var chunk = msg.subarray(i, Math.min(i + 16, msg.length));
      acc = ((acc + leBig(chunk) + (BigInt(1) << BigInt(8 * chunk.length))) * r) % p;
    }
    acc = (acc + s) & ((BigInt(1) << BigInt(128)) - BigInt(1));
    var tag = new Uint8Array(16);
    for (var t = 0; t < 16; t++) { tag[t] = Number(acc & BigInt(255)); acc >>= BigInt(8); }
    return tag;
  }
  function pad16(n) { return (16 - (n % 16)) % 16; }
  function le64(n) { var b = new Uint8Array(8); for (var i = 0; i < 6; i++) { b[i] = n & 255; n = Math.floor(n / 256); } return b; }
  /** ciphertext || 16-byte tag, as Java's ChaCha20-Poly1305 gives it. */
  function seal(key, nonce, plain, aad) {
    var otk = block(key, 0, nonce).subarray(0, 32);
    var ct = chacha(key, 1, nonce, plain);
    var mac = new Uint8Array(aad.length + pad16(aad.length) + ct.length + pad16(ct.length) + 16);
    var o = 0;
    mac.set(aad, o); o += aad.length + pad16(aad.length);
    mac.set(ct, o); o += ct.length + pad16(ct.length);
    mac.set(le64(aad.length), o); mac.set(le64(ct.length), o + 8);
    var out = new Uint8Array(ct.length + 16);
    out.set(ct, 0); out.set(poly1305(otk, mac), ct.length);
    return out;
  }
  function b64urlDecode(s) {
    s = s.replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function b64urlEncode(b) {
    var bin = "";
    for (var i = 0; i < b.length; i++) bin += String.fromCharCode(b[i]);
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  /** The body to post: nonce || sealed text, base64url; the key from the link's fragment, bound to its path. */
  function sealText(keyB64, path, text) {
    var nonce = new Uint8Array(12);
    crypto.getRandomValues(nonce);
    var sealed = seal(b64urlDecode(keyB64), nonce, new TextEncoder().encode(text), new TextEncoder().encode(path));
    var out = new Uint8Array(12 + sealed.length);
    out.set(nonce, 0); out.set(sealed, 12);
    return b64urlEncode(out);
  }
  return { seal: seal, sealText: sealText, b64urlDecode: b64urlDecode, b64urlEncode: b64urlEncode };
})();
if (typeof module !== "undefined") module.exports = HearthSeal;
