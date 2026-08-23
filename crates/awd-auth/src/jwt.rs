//! Minimal HS256 JWT (mint + verify) with a `jti` session identifier.
//!
//! AshAuthentication signed session tokens HS256 with the app secret and used
//! the `jti` claim as the session key (the DB token-presence check, deferred,
//! revokes by `jti`). We own the envelope here — header/payload base64url,
//! HMAC-SHA256 signature, constant-time verify, expiry check — so it's pure and
//! testable with no heavy crypto deps.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// JWT claims. `sub` = user id, `jti` = session id (revocation key),
/// `purpose` = token purpose (e.g. "user"), `iat`/`exp` = unix seconds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub jti: String,
    pub purpose: String,
    pub iat: i64,
    pub exp: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum JwtError {
    #[error("malformed token")]
    Malformed,
    #[error("invalid signature")]
    InvalidSignature,
    #[error("token expired")]
    Expired,
}

/// A fresh random `jti` (128 bits, hex).
pub fn new_jti() -> String {
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

fn sign(secret: &[u8], signing_input: &str) -> String {
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key length");
    mac.update(signing_input.as_bytes());
    URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
}

/// Mint a signed HS256 token for `claims`.
pub fn mint(secret: &[u8], claims: &Claims) -> String {
    let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"HS256","typ":"JWT"}"#);
    let payload = URL_SAFE_NO_PAD.encode(serde_json::to_vec(claims).expect("claims serialize"));
    let signing_input = format!("{header}.{payload}");
    let signature = sign(secret, &signing_input);
    format!("{signing_input}.{signature}")
}

/// Verify signature + expiry and return the claims. `now_unix` is the current
/// time in unix seconds (injected for testability).
pub fn verify(secret: &[u8], token: &str, now_unix: i64) -> Result<Claims, JwtError> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err(JwtError::Malformed);
    }
    let signing_input = format!("{}.{}", parts[0], parts[1]);
    let expected = sign(secret, &signing_input);

    if !ct_eq(expected.as_bytes(), parts[2].as_bytes()) {
        return Err(JwtError::InvalidSignature);
    }

    let payload_bytes = URL_SAFE_NO_PAD
        .decode(parts[1])
        .map_err(|_| JwtError::Malformed)?;
    let claims: Claims = serde_json::from_slice(&payload_bytes).map_err(|_| JwtError::Malformed)?;

    if now_unix >= claims.exp {
        return Err(JwtError::Expired);
    }
    Ok(claims)
}

/// Constant-time byte comparison (avoids signature timing leaks).
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

    fn claims(exp: i64) -> Claims {
        Claims {
            sub: "user-1".into(),
            jti: "session-abc".into(),
            purpose: "user".into(),
            iat: 1_000,
            exp,
        }
    }

    #[test]
    fn mint_then_verify_roundtrip() {
        let secret = b"super-secret";
        let token = mint(secret, &claims(2_000));
        let got = verify(secret, &token, 1_500).unwrap();
        assert_eq!(got.sub, "user-1");
        assert_eq!(got.jti, "session-abc");
        assert_eq!(got.purpose, "user");
    }

    #[test]
    fn wrong_secret_rejected() {
        let token = mint(b"secret-a", &claims(2_000));
        assert_eq!(
            verify(b"secret-b", &token, 1_500),
            Err(JwtError::InvalidSignature)
        );
    }

    #[test]
    fn tampered_payload_rejected() {
        let token = mint(b"s", &claims(2_000));
        let mut parts: Vec<&str> = token.split('.').collect();
        let forged = URL_SAFE_NO_PAD
            .encode(br#"{"sub":"admin","jti":"x","purpose":"user","iat":0,"exp":9999999999}"#);
        parts[1] = &forged;
        let tampered = parts.join(".");
        assert_eq!(
            verify(b"s", &tampered, 1_500),
            Err(JwtError::InvalidSignature)
        );
    }

    #[test]
    fn expired_rejected_at_boundary() {
        let token = mint(b"s", &claims(2_000));
        assert!(verify(b"s", &token, 1_999).is_ok());
        assert_eq!(verify(b"s", &token, 2_000), Err(JwtError::Expired)); // exp is exclusive
    }

    #[test]
    fn malformed_rejected() {
        assert_eq!(verify(b"s", "not.a", 0), Err(JwtError::Malformed));
        assert_eq!(verify(b"s", "only-one-part", 0), Err(JwtError::Malformed));
    }

    #[test]
    fn jti_is_random_and_hex() {
        let a = new_jti();
        let b = new_jti();
        assert_ne!(a, b);
        assert_eq!(a.len(), 32);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
    }
}
