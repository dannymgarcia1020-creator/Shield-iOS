# Shield (iOS) — Local-First Mobile Digital Forensics & Camouflage Vault

## The Mission
Shield was engineered by an independent Arizona developer to provide ironclad, offline legal protection for vulnerable individuals, citizen journalists, and survivors of harassment. In high-stakes situations, cloud data can be intercepted, and local photos can be easily deleted or altered. Shield provides an un-compromised digital chain of custody entirely on-device.

## Technical Core Architecture
* **Isolated Sandbox Storage:** Bypasses standard apple photo caches using an independent, isolated `FileManager` library directory structure.
* **Immediate Cryptographic Signatures:** Calculates automatic SHA-256 asset hashes via `CryptoKit` the exact moment media touches local storage.
* **Camouflage UI Intercept:** Employs an instantaneous URL-Scheme trigger that suspends the active vault and shifts cleanly to an innocent system application when safety is compromised.
* **Pristine PDF Compilation Engine:** Uses a specialized dynamic layout loop inside `UIGraphicsPDFRenderer`. It extracts uncompressed raw file values from local storage and maps custom aspect-ratio bounds, generating crystal-clear, courtroom-ready legal evidence documents without thumbnail distortion.

## Accessibility & Trauma-Informed Engineering Note
As an independent developer navigating epilepsy, I intentionally designed Shield's user interface to completely avoid rapid flashing animations, erratic transitions, or high-contrast strobe visual cues. The result is a highly stable, calming, and reliable environment built specifically to perform cleanly when users are operating under extreme stress.
