//! AEAD encryption for customer-provided secrets (AWS secret access keys
//! algorithm: XChaCha20-Poly1305 (24-byte random nonce + 16-byte tag).
//! storage shape: [nonce(24) || ciphertext + tag].

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use chacha20poly1305::{
    aead::{Aead, KeyInit, OsRng},
    AeadCore, XChaCha20Poly1305, XNonce,
};

use crate::error::AppError;

const NONCE_LEN: usize = 24;

fn cipher() -> Result<XChaCha20Poly1305, AppError> {
    let raw = std::env::var("SF_VOICE_SECRETS_KEY").map_err(|_| {
        AppError::Internal(
            "SF_VOICE_SECRETS_KEY not set — add it to `.env` at the repo root. \
             generate 32 bytes via `openssl rand -base64 32` (the value in .env.example is fine for dev). \
             restart `mise run core:dev` after editing."
                .into(),
        )
    })?;
    // accept hex (64 chars) or base64 (with or without padding).
    let key_bytes: Vec<u8> = if raw.len() == 64 && raw.chars().all(|c| c.is_ascii_hexdigit()) {
        (0..64)
            .step_by(2)
            .map(|i| u8::from_str_radix(&raw[i..i + 2], 16))
            .collect::<Result<_, _>>()
            .map_err(|e| AppError::Internal(format!("SF_VOICE_SECRETS_KEY hex decode: {e}")))?
    } else {
        B64.decode(raw.trim())
            .map_err(|e| AppError::Internal(format!("SF_VOICE_SECRETS_KEY base64 decode: {e}")))?
    };
    if key_bytes.len() != 32 {
        return Err(AppError::Internal(format!(
            "SF_VOICE_SECRETS_KEY must decode to 32 bytes, got {}",
            key_bytes.len()
        )));
    }
    Ok(XChaCha20Poly1305::new(key_bytes.as_slice().into()))
}

pub fn encrypt(plaintext: &[u8]) -> Result<Vec<u8>, AppError> {
    let cipher = cipher()?;
    let nonce = XChaCha20Poly1305::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|e| AppError::Internal(format!("encrypt: {e}")))?;
    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

pub fn decrypt(blob: &[u8]) -> Result<Vec<u8>, AppError> {
    if blob.len() <= NONCE_LEN {
        return Err(AppError::Internal("encrypted blob too short".into()));
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);
    let nonce = XNonce::from_slice(nonce_bytes);
    let cipher = cipher()?;
    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| AppError::Internal(format!("decrypt: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrips() {
        std::env::set_var(
            "SF_VOICE_SECRETS_KEY",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", // 44 b64 = 32 bytes
        );
        let plain = b"AKIA-secret-thing";
        let blob = encrypt(plain).expect("encrypt");
        let out = decrypt(&blob).expect("decrypt");
        assert_eq!(out, plain);
    }
}
