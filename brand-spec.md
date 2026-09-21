# Nana entry design

## Current source of truth

The user-supplied board showing Icon / Launch / Login / Registration / Profile completion supersedes the initial harbor-style exploration for these entry surfaces. The requested implementation stays native SwiftUI. Scope for this iteration is the icon, launch, login, and registration only.

## Visual decisions

- Reuse the supplied red/violet/blue-to-black full-screen artwork without recreating its gradient.
- Keep the logo embedded in the background; never add a second logo over it.
- Centered aspect fill, edge to edge, without top or bottom background insets.
- White input values, muted white labels, violet image buttons, lilac text links.
- Thin underlines, capsule primary actions, approximately 30pt form margins on a 390pt canvas.
- Native text inputs use 14pt text and 12pt labels; action assets retain their original label artwork.
- Tappable controls have at least a 44pt height. Keyboard presentation keeps the form scrollable.
- Correct the design's password placeholder from “Your email” to “Your password”.

## Asset mapping

| Export in assets/photos | Catalog resource | Embedded content |
| --- | --- | --- |
| 编组@2x(120).png | AppIcon | Complete square icon artwork |
| 编组@2x(121).png | NanaLaunchArtwork | Background and centered logo |
| 编组备份 2@2x(17).png | NanaAccountArtwork | Background and upper logo |
| 编组备份@2x(13).png | NanaPlainArtwork | Background only, reserved for next screen |
| 编组@2x(103).png | NanaLoginAction | Button and Log in text |
| 编组备份 3@2x(15).png | NanaRegistrationAction | Button and Next text |
| 编组@2x(104).png | NanaAppleAction | Outline button, Apple mark, and sign-in text |
| 图形备份 5@2x(7).png | NanaClearEntry | Orange clear control |
| 图形备份 6@2x(11).png | NanaPasswordHidden | Closed eye |
| 图形备份 7@2x(6).png | NanaPasswordVisible | Open eye |

No generated imagery was needed. Original exports are preserved. Taste was evaluated and excluded because it explicitly excludes native mobile. Design guidance was applied to reference fidelity and asset reuse. Garden image guidance was evaluated; existing complete assets made generation unnecessary. No HTML or browser artifact is part of this iteration.

## Account consent and loading

- The consent row is part of the login/register action area. The checkbox covers both supplied legal documents and starts unchecked on every fresh screen session.
- Submission and Apple entry paths call the same consent gate. If it is unchecked, a custom modal uses the same near-black, violet, lilac, and white palette; no spinner is shown and no submission task starts.
- The supplied links open in a native, non-persistent WKWebView sheet: `https://sites.google.com/view/nana-terms-of-service/future` and `https://sites.google.com/view/nana-privacy-policy/future`.
- The launch loading state uses an orbiting lilac/fluorescent-green point over the launch artwork. The account submission loading state uses three breathing vertical bars in a compact modal. Both pause their animation for Reduce Motion.
- Loading states block duplicate interaction and cancel cleanly when the entry view disappears.

## Review notes

Product differentiation must come from actual product behavior, content, and design, not renamed classes. Names describe account entry and its state without concealment. No claim of guaranteed App Store approval is made.

## Extended entry state machine

`NanaEntryCoordinator` owns the visible state: launch loading, onboarding, landing, account login, account registration, profile completion, or the authenticated shell. `NanaSessionStore` persists onboarding completion and the completed local profile. A pending identity is retained if the app is closed between credentials and profile completion.

- Email login uses `Start` and waits 3.4 seconds in the account submission loading treatment before checking the local Keychain credential.
- Email registration uses `Sign up`, waits 3.4 seconds, stores the Keychain credential, then opens profile completion.
- Apple entry uses the real AuthenticationServices controller and waits on its callback; the Apple credential's returned name is the profile name seed.
- Profile completion blocks `Next` until name, gender, country, and at least one tag exist. A library or camera image may be attached as avatar data.

## A-side 1.0 live-room direction

The authenticated product surface follows the Lanhu `88-直播3` prototype: near-black space, violet and indigo light, neon pink accents, compact rounded controls, and image-led live-room cards. The primary navigation is Live, Rooms, Messages, and Me. The home feed, voice-room stage, post detail, conversation, profile, wallet, check-in, collection, level and moderation surfaces use a single visual vocabulary but keep their business semantics distinct.

The A-side uses a fixed `NanaMockPayload.json` seed plus `NanaMockStore` as a local mutation overlay. Pre-recorded stage artwork is intentionally labeled as a local simulated stream in the room detail so it can be replaced by a real stream source later without claiming remote live presence. Portraits, covers and room video remain placeholders until the final media set is supplied.
