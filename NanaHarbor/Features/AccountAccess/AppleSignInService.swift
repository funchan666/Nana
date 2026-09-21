import AuthenticationServices
import UIKit

struct AppleIdentityResult {
    let stableIdentity: String
    let emailAddress: String?
    let displayName: String?
}

@MainActor
final class AppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((Result<AppleIdentityResult, Error>) -> Void)?

    func begin(completion: @escaping (Result<AppleIdentityResult, Error>) -> Void) {
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion?(.failure(AppleSignInError.unexpectedCredential))
            completion = nil
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let name = credential.fullName.flatMap { formatter.string(from: $0) }
        completion?(.success(AppleIdentityResult(stableIdentity: credential.user, emailAddress: credential.email, displayName: name)))
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }
}

enum AppleSignInError: LocalizedError {
    case unexpectedCredential
    var errorDescription: String? { "Apple sign-in did not return a usable account." }
}
