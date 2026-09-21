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
    private var authorizationController: ASAuthorizationController?
    private var expectedState: String?

    func begin(completion: @escaping (Result<AppleIdentityResult, Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let state = UUID().uuidString
        expectedState = state
        request.state = state
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              !credential.user.isEmpty, credential.state == expectedState else {
            finish(.failure(AppleSignInError.unexpectedCredential))
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let name = credential.fullName.flatMap { formatter.string(from: $0) }
        finish(.success(AppleIdentityResult(stableIdentity: credential.user, emailAddress: credential.email, displayName: name)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<AppleIdentityResult, Error>) {
        let callback = completion
        completion = nil
        expectedState = nil
        authorizationController = nil
        callback?(result)
    }
}

enum AppleSignInError: LocalizedError {
    case unexpectedCredential
    var errorDescription: String? { "Apple sign-in did not return a usable account." }
}
