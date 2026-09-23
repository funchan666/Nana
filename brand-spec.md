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

## Message detail screens — supplied reference alignment

Notification list/details, Friends/New, personal album and private conversation now use full-screen native presentations with `NanaTabBackdrop`, compact 44pt navigation and outlined back controls. Taste and Garden routing were evaluated; their web/raster generation workflows are unnecessary for this native revision. Claude Design guidance informs hierarchy, reference fidelity and reuse of the supplied artwork.

- Notification rows use charcoal surfaces and an account-local unread badge. Each bundled community reminder opens its own text; the clear/read control marks both read atomically. No invented update dates are displayed.
- Friends/New sits in the top navigation. The Friends tab retains the reference's three statistic tiles and pink message/purple call actions. Confirmed mutual friends and new followers come from the private inbox; unavailable call totals use a dash instead of fixture numbers or fabricated call outcomes.
- The personal album has date-grouped, square three-column thumbnails, full-image preview, selection checks, select-all and a pinned upload/delete footer. Another person's album never includes this account's private photos. Empty albums remain empty.
- Conversation details use a compact profile card, gray incoming and violet outgoing bubbles, timestamps, a capsule composer and expandable photo/emoji/call/gift controls. Report/block remains in the top-right menu. Emoji edits the draft; unavailable delivery preserves it. Messaging/calling/attachment transports have not been fabricated.
- Source and project-file checks only; no compilation, tests, app launch or simulator review were performed.

## My Profile secondary screens — supplied reference alignment

Profile destinations use full-screen SwiftUI pages, the existing red/violet-to-black backdrop, compact centered titles and outlined back controls. Relationship and blacklist cards use portrait thumbnails and deep navy surfaces; wallet, check-in and level pages reuse the original `NanaWalletArtwork`, `NanaCheckInArtwork` and `NanaLevelGem` resources. Store and backpack use the eight supplied room-gift icons in four columns. Settings use grouped charcoal rows and YES/NO preference controls.

- Followers, Following and Friends retain their separate data sources and genuine empty states. The calendar uses the current month and account-local check-in history; profile, check-in and level displays share the same activity level.
- Profile editing saves the portrait, nickname, birthday, country, gender, interests and signature. Existing profiles decode without a signature, and image imports are resized before protected account storage.
- Feedback has a topic, details and pinned submit control. Submission currently saves locally and explicitly reports that scope. Privacy and notice choices persist locally.
- Wallet purchases retain the existing StoreKit verification flow. Store inventory purchasing and account deletion remain unavailable rather than fabricating success. Logout, account switching and cache clearing use custom confirmation panels.
- Static source/resource checks only. No compilation, tests, app launch or simulator inspection was performed for this revision.

Wallet refinement follows the supplied reference's compact balance typography, overlapping full-width recharge surface, charcoal rows, larger coin artwork and smaller capsule price controls. The first price control is orange; the remaining controls are violet. All seven product identifiers, coin amounts, localized/fallback prices, balances and purchase behavior remain unchanged. The reference's illustrative discounts, crossed-out values and countdown are not added as product information.

Check-in refinement preserves the original 700 × 1238 artwork aspect ratio and positions the hero/calendar content against its binding rings. It uses centered `yyyy/MM` month navigation, complete Monday-first weeks based on each month's actual length, charcoal date cells, a violet progress track and a full-width Clock in capsule. The bottom strip describes the existing free daily reward. Actual check-in dates and the once-per-day 10-point local save remain unchanged; paid check-in and retroactive purchase prices from the mockup are not introduced.

## Original Messages empty-state illustrations

The two Messages empty states use newly generated Nana artwork instead of system-symbol tiles. `NanaEmptyFriendsLive` is a lavender miniature camera and ivory speech bubble; `NanaEmptyConversations` is a pair of sculptural speech bubbles with a violet connecting ribbon. Both are transparent PNGs with no baked-in text. Original generation used the host-native image tool, guided by Garden `gpt-image-2` and the imagegen skill; the full prompt specifications are saved in `garden-gpt-image-2/prompt/nana-empty-*-20260923.json`. No downloaded stock art or existing mascot was used as input.

The friends state is a compact horizontal card with a View friends action. The conversation state uses centered artwork, shorter explanatory copy and a Find people action leading to search. Artwork is decorative for VoiceOver; text scales, and the live card switches to a vertical layout at accessibility text sizes. The existing real-data empty conditions and populated lists are preserved. Asset transparency, catalog registration and diff formatting were inspected without building or launching the app.
