import SwiftUI
import AuthenticationServices
import CryptoKit
import Foundation

/// The parts of a Sign in with Apple result the app needs, extracted on the
/// main actor so that only Sendable values travel further.
struct AppleCredential: Sendable {
    let idToken: String
    let rawNonce: String
    let authorizationCode: String?
    let fullName: String?

    /// Returns nil when the user cancelled the sheet.
    static func from(_ result: Result<ASAuthorization, any Error>, rawNonce: String) throws -> AppleCredential? {
        switch result {
        case let .failure(error):
            if let error = error as? ASAuthorizationError, error.code == .canceled { return nil }
            throw error
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                throw URLError(.userAuthenticationRequired)
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = credential.fullName?.formatted(.name(style: .medium))
            return AppleCredential(
                idToken: idToken,
                rawNonce: rawNonce,
                authorizationCode: code,
                fullName: name?.trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// "Sign in with Apple" button that hands a ready credential to `onCredential`.
struct AppleSignInButton: View {
    var label: SignInWithAppleButton.Label = .signIn
    var onCredential: (AppleCredential) -> Void
    var onError: (any Error) -> Void

    @State private var rawNonce = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(label) { request in
            rawNonce = AppleNonce.random()
            request.requestedScopes = [.fullName]
            request.nonce = AppleNonce.sha256(rawNonce)
        } onCompletion: { result in
            do {
                if let credential = try AppleCredential.from(result, rawNonce: rawNonce) {
                    onCredential(credential)
                }
            } catch {
                onError(error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
    }
}
