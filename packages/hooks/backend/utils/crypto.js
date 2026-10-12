const { createCipheriv, createDecipheriv, randomBytes, scryptSync } = require("node:crypto");

const IV_BYTES = 12;
const TAG_BYTES = 16;
const VERSION_BYTES = 1;

const ALGORITHMS = {
    "aes-256-gcm": { keyBytes: 32, version: 0x01 },
    "aes-128-gcm": { keyBytes: 16, version: 0x02 },
};

const BY_VERSION = Object.fromEntries(
    Object.entries(ALGORITHMS).map(([name, meta]) => [meta.version, { name, ...meta }]),
);

const DEFAULT_ALGORITHM = "aes-256-gcm";
const DEFAULT_SALT = "default-salt";

function metaFor(algorithm) {
    const meta = ALGORITHMS[algorithm];
    if (!meta) {
        const supported = Object.keys(ALGORITHMS).join(", ");
        throw new RangeError(`unsupported algorithm: ${algorithm}. Supported: ${supported}`);
    }
    return meta;
}

function resolveKey(key, keyBytes, salt) {
    if (Buffer.isBuffer(key) && key.length === keyBytes) return key;
    if (typeof key === "string") {
        // Accept hex or base64 raw keys of the exact length; otherwise derive via scrypt.
        if (new RegExp(`^[0-9a-f]{${keyBytes * 2}}$`, "i").test(key)) return Buffer.from(key, "hex");
        const b64 = Buffer.from(key, "base64");
        if (b64.length === keyBytes) return b64;
        return scryptSync(key, salt, keyBytes);
    }
    throw new TypeError(`key must be a ${keyBytes}-byte Buffer, hex/base64 string, or passphrase`);
}

function encrypt(plaintext, key, { algorithm = DEFAULT_ALGORITHM, salt = DEFAULT_SALT } = {}) {
    const { keyBytes, version } = metaFor(algorithm);
    const versionByte = Buffer.from([version]);
    const iv = randomBytes(IV_BYTES);
    const cipher = createCipheriv(algorithm, resolveKey(key, keyBytes, salt), iv);
    cipher.setAAD(versionByte); // bind the version tag to the auth check
    const ct = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    return Buffer.concat([versionByte, iv, ct, cipher.getAuthTag()]).toString("base64url");
}

function decrypt(encrypted, key, { salt = DEFAULT_SALT } = {}) {
    const buf = Buffer.from(encrypted, "base64url");
    if (buf.length < VERSION_BYTES + IV_BYTES + TAG_BYTES) throw new Error("invalid token");
    const versionByte = buf.subarray(0, VERSION_BYTES);
    const meta = BY_VERSION[versionByte[0]];
    if (!meta) throw new Error(`unknown token version: 0x${versionByte[0].toString(16).padStart(2, "0")}`);
    const iv = buf.subarray(VERSION_BYTES, VERSION_BYTES + IV_BYTES);
    const tag = buf.subarray(buf.length - TAG_BYTES);
    const ct = buf.subarray(VERSION_BYTES + IV_BYTES, buf.length - TAG_BYTES);
    const decipher = createDecipheriv(meta.name, resolveKey(key, meta.keyBytes, salt), iv);
    decipher.setAAD(versionByte);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ct), decipher.final()]).toString("utf8");
}

module.exports = {
    DEFAULT_ALGORITHM,
    DEFAULT_SALT,
    encrypt,
    decrypt,
};
