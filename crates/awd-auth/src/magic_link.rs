//! Magic-link token generation/verification.
//!
//! A high-entropy random token is emailed in the sign-in link; only its
//! SHA-256 hash is stored server-side (so a DB leak doesn't yield usable
//! links). On consume, the presented token is hashed and compared
//! constant-time to the stored hash, subject to expiry (checked by the caller
//! against the stored row).

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use sha2::{Digest, Sha256};

/// Default magic-link validity window (seconds). AshAuthentication's default
/// magic-link token lifetime; the caller stamps `expires_at = now + this`.
pub const DEFAULT_TTL_SECONDS: i64 = 15 * 60;

/// A generated magic-link token: the `raw` value goes in the emailed link, the
/// `hash` is what gets stored.
#[derive(Debug, Clone)]
pub struct GeneratedToken {
    pub raw: String,
    pub hash: String,
}

/// Generate a new token (256 bits of entropy, URL-safe) + its storage hash.
pub fn generate() -> GeneratedToken {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    let raw = URL_SAFE_NO_PAD.encode(bytes);
    let hash = hash_token(&raw);
    GeneratedToken { raw, hash }
}

/// `lower_hex(sha256(raw))` — the value stored server-side.
pub fn hash_token(raw: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(raw.as_bytes());
    hex::encode(hasher.finalize())
}

/// Verify a presented token against the stored hash (constant-time). Expiry is
/// the caller's responsibility (compare the stored `expires_at` to now).
pub fn verify_token(presented_raw: &str, stored_hash: &str) -> bool {
    ct_eq(hash_token(presented_raw).as_bytes(), stored_hash.as_bytes())
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b) {
        diff |= x ^ y;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_tokens_are_unique_and_hash_stored() {
        let a = generate();
        let b = generate();
        assert_ne!(a.raw, b.raw);
        assert_ne!(a.hash, b.hash);
        assert_eq!(a.hash, hash_token(&a.raw));
        assert_eq!(a.hash.len(), 64); // sha256 hex
    }

    #[test]
    fn verify_accepts_matching_rejects_tampered() {
        let t = generate();
        assert!(verify_token(&t.raw, &t.hash));
        assert!(!verify_token("not-the-token", &t.hash));
        // A leaked hash is not a usable token: hashing the hash != the hash.
        assert!(!verify_token(&t.hash, &t.hash));
    }
}
