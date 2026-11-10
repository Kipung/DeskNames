# Persistent development signing

The default build is ad-hoc signed. Its designated requirement is tied to the specific build, so changing the code can invalidate an earlier Accessibility grant even when System Settings still shows the app enabled. A consistent certificate and bundle identifier give macOS an identity that can match later builds. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/).

For this guest's local development, use a dedicated persistent code-signing certificate. An Apple-issued development identity also works. Apple documents self-signed identities for internal testing in [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html). A local self-signed certificate does not establish a notarized public distribution identity.

If no suitable identity exists, the guest user can create one in Keychain Access → Certificate Assistant → Create a Certificate, named `DeskNames VM Development`, with Identity Type `Self Signed Root` and Certificate Type `Code Signing`, stored in the login keychain. Keep the private key in the guest keychain. OS authorization and private-key access prompts must be handled by the user. Do not export the key into the repository or grant unrelated applications access to it.

List identities with `security find-identity -p codesigning`. Put the chosen certificate's complete 40-character SHA-1 fingerprint on one line in:

```text
~/Library/Application Support/DeskNames Development/signing-identity.txt
```

`build.sh` and the guest build/test wrapper then reuse that identity. If the configuration is malformed or the identity is missing, the build stops before compilation; it does not silently switch back to ad-hoc signing. The configuration contains only a public certificate fingerprint. An explicit `DESKNAMES_SIGN_IDENTITY` environment variable can select another certificate by fingerprint or full name; `DESKNAMES_SIGN_IDENTITY_FILE` can select another configuration file. Explicit `DESKNAMES_SIGN_IDENTITY=-` requests ad-hoc signing.

After switching from ad-hoc to certificate signing, approve the certificate-signed app in Accessibility once. Continue using the same bundle identifier, certificate and app location. Verify the designated requirement and actual Accessibility trust after a changed signed build before claiming approval persistence. Certificate replacement, deletion, OS changes or other privacy-policy behavior can still require user action.

Signing configuration does not grant Accessibility, change TCC records, disable Gatekeeper or alter SIP. Preserve all normal macOS protections. Do not replace the designated requirement with a bundle-identifier-only rule.
