// The phone pages' ChaCha20-Poly1305 (android/app/src/main/res/raw/phone_seal.js) against Node's own, and RFC 8439's
// AEAD test vector (2.8.2). Run: node test/js/phone_seal_test.js
const assert = require("assert");
const crypto = require("crypto");
const path = require("path");
const HearthSeal = require(path.join(__dirname, "../../android/app/src/main/res/raw/phone_seal.js"));

function nodeSeal(key, nonce, plain, aad) {
  const c = crypto.createCipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 });
  c.setAAD(aad, { plaintextLength: plain.length });
  return Buffer.concat([c.update(plain), c.final(), c.getAuthTag()]);
}

// RFC 8439 2.8.2
const key = Buffer.from("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f", "hex");
const nonce = Buffer.from("070000004041424344454647", "hex");
const aad = Buffer.from("50515253c0c1c2c3c4c5c6c7", "hex");
const plain = Buffer.from("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
const sealed = Buffer.from(HearthSeal.seal(new Uint8Array(key), new Uint8Array(nonce), new Uint8Array(plain), new Uint8Array(aad)));
assert.strictEqual(sealed.subarray(sealed.length - 16).toString("hex"), "1ae10b594f09e26a7e902ecbd0600691");
assert.deepStrictEqual(sealed, nodeSeal(key, nonce, plain, aad));

// Random sizes, around the 16- and 64-byte edges
for (let n = 0; n < 300; n++) {
  const k = crypto.randomBytes(32), iv = crypto.randomBytes(12);
  const p = crypto.randomBytes(n % 150), a = crypto.randomBytes(n % 37);
  const mine = Buffer.from(HearthSeal.seal(new Uint8Array(k), new Uint8Array(iv), new Uint8Array(p), new Uint8Array(a)));
  assert.deepStrictEqual(mine, nodeSeal(k, iv, p, a), "size " + p.length + "/" + a.length);
}

// sealText's body opens with the key and the path as additional data
const k = crypto.randomBytes(32);
const body = Buffer.from(HearthSeal.sealText(HearthSeal.b64urlEncode(new Uint8Array(k)), "/secret", "{\"pins\":[]}")
  .replace(/-/g, "+").replace(/_/g, "/"), "base64");
const d = crypto.createDecipheriv("chacha20-poly1305", k, body.subarray(0, 12), { authTagLength: 16 });
d.setAAD(Buffer.from("/secret"), { plaintextLength: body.length - 28 });
d.setAuthTag(body.subarray(body.length - 16));
assert.strictEqual(Buffer.concat([d.update(body.subarray(12, body.length - 16)), d.final()]).toString(), "{\"pins\":[]}");
console.log("phone_seal: ok");
