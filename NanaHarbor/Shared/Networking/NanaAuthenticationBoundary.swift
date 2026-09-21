import Foundation

/// The published A-side export contains no account, Apple credential exchange,
/// refresh-token, logout or registration route. These types keep that boundary
/// explicit without inventing a URL. Not used by the device-local entry flow in
/// NanaSessionStore; local membership does not issue or require a server Token.
struct NanaCredentialSignInRequest: Encodable {
    let emailAddress: String
    let password: String
}

struct NanaAppleCredentialExchangeRequest: Encodable {
    let authorizationCode: String
    let identityToken: String
    let userIdentifier: String
}

struct NanaSessionToken: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

struct NanaAuthenticationFailure: Decodable {
    let code: String
    let message: String
}

struct NanaAuthenticationBoundary {
    func signIn(_ request: NanaCredentialSignInRequest) async throws -> NanaSessionToken {
        throw NanaAServiceError.authenticationUnavailable
    }

    func exchangeAppleCredential(_ request: NanaAppleCredentialExchangeRequest) async throws -> NanaSessionToken {
        throw NanaAServiceError.authenticationUnavailable
    }

    func refresh(_ token: NanaSessionToken) async throws -> NanaSessionToken {
        throw NanaAServiceError.authenticationUnavailable
    }

    func register(_ request: NanaCredentialSignInRequest) async throws -> NanaSessionToken {
        throw NanaAServiceError.authenticationUnavailable
    }

    func logout() async throws {
        throw NanaAServiceError.authenticationUnavailable
    }
}
