import Foundation
import CryptoKit

// Verify released bytes using only the committed public key, never the Keychain.
let args = CommandLine.arguments
if args.count < 3 { fatalError("Usage: verify-update PUBLIC_KEY FILE [ARCHIVE_SIGNATURE]") }
let encodedKey = try String(contentsOfFile: args[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let rawKey = Data(base64Encoded: encodedKey) else { fatalError("Invalid public key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
let content: Data
let signature: Data
if args.count == 4 {
    guard let decoded = Data(base64Encoded: args[3]) else { fatalError("Invalid signature") }
    signature = decoded; content = data
} else {
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let range = data.range(of: marker, options: .backwards),
          let block = String(data: data[range.lowerBound...], encoding: .utf8) else { fatalError("Missing signed-feed block") }
    let lines = block.components(separatedBy: "\n")
    guard lines.count == 5, lines[0] == "<!-- sparkle-signatures:", lines[3] == "-->", lines[4].isEmpty,
          lines[1].hasPrefix("edSignature: "), lines[2].hasPrefix("length: "),
          let decoded = Data(base64Encoded: String(lines[1].dropFirst(13))),
          let length = Int(lines[2].dropFirst(8)), length == range.lowerBound else { fatalError("Invalid signed-feed block") }
    signature = decoded; content = data.prefix(length)
}
guard key.isValidSignature(signature, for: content) else {
    fputs("FAIL: update signature does not match published bytes\n", stderr)
    exit(1)
}
print("PASS: public-key signature verification")
