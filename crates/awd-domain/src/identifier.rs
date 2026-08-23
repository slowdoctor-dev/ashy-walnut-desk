//! Identifier & email hashing. Ports `identity/changes/hash_primary_identifier.ex`
//! and the email-hash change in `accounts/user.ex`.
//!
//! The raw identifier is normalized (strip whitespace/hyphens/parens, lowercase),
//! validated as E.164 (`^\+\d{6,15}$`), then hashed:
//! `lower_hex(sha256(normalized ++ salt))`. The hash is the lookup key (unique
//! index); the normalized raw form is stored separately as send payload.
//!
//! **The same `identifier_hash_salt` secret used by the Elixir deployment MUST
//! be configured here**, or every hash (and the unique indexes) diverges.

use regex::Regex;
use sha2::{Digest, Sha256};
use std::sync::OnceLock;

fn e164_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\+\d{6,15}$").unwrap())
}

fn strip_re() -> &'static Regex {
    // Elixir: ~r/[\s\-().]/u — strip whitespace, hyphen, parens, dot.
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"[\s\-().]").unwrap())
}

/// `String.replace(raw, ~r/[\s\-().]/u, "") |> String.downcase()`.
pub fn normalize_identifier(raw: &str) -> String {
    strip_re().replace_all(raw, "").to_lowercase()
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("primary identifier must be E.164 (e.g. +15551234567)")]
pub struct InvalidIdentifier;

/// Normalize + validate + hash. Returns `(normalized, hash)`.
pub fn hash_primary_identifier(
    raw: &str,
    salt: &str,
) -> Result<(String, String), InvalidIdentifier> {
    let normalized = normalize_identifier(raw);
    if !e164_re().is_match(&normalized) {
        return Err(InvalidIdentifier);
    }
    let hash = sha256_salted_hex(&normalized, salt);
    Ok((normalized, hash))
}

/// `lower_hex(sha256(lowercase(trim(email)) ++ salt))`.
pub fn hash_email(email: &str, salt: &str) -> String {
    let normalized = email.trim().to_lowercase();
    sha256_salted_hex(&normalized, salt)
}

/// `lower_hex(sha256(input ++ salt))` — update order matches `input <> salt`.
fn sha256_salted_hex(input: &str, salt: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hasher.update(salt.as_bytes());
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    const SALT: &str = "test-salt";

    #[test]
    fn normalizes_human_formatted_number() {
        assert_eq!(normalize_identifier("+1 (555) 123-4567"), "+15551234567");
    }

    #[test]
    fn rejects_non_e164() {
        assert_eq!(
            hash_primary_identifier("5551234567", SALT),
            Err(InvalidIdentifier)
        );
        assert_eq!(hash_primary_identifier("", SALT), Err(InvalidIdentifier));
        assert_eq!(hash_primary_identifier("+12", SALT), Err(InvalidIdentifier)); // <6 digits
        assert!(hash_primary_identifier("+1234567890123456", SALT).is_err()); // >15 digits
    }

    #[test]
    fn hash_is_deterministic_lowercase_hex_and_salted() {
        let (norm, hash) = hash_primary_identifier("+15551234567", SALT).unwrap();
        assert_eq!(norm, "+15551234567");
        assert_eq!(hash.len(), 64);
        assert!(hash
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));

        // Equals sha256("+15551234567test-salt").
        let expected = {
            let mut h = Sha256::new();
            h.update(b"+15551234567test-salt");
            hex::encode(h.finalize())
        };
        assert_eq!(hash, expected);

        // Salt actually participates.
        let (_, other) = hash_primary_identifier("+15551234567", "other").unwrap();
        assert_ne!(hash, other);
    }

    #[test]
    fn email_hash_trims_and_lowercases() {
        assert_eq!(
            hash_email("  Foo@Example.COM ", SALT),
            hash_email("foo@example.com", SALT)
        );
    }
}
