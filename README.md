# Nana

Nana is a SwiftUI iOS 17 live-room social prototype. The A-side follows the purple `88-直播3` direction from the Lanhu reference and reads a typed JSON baseline with persisted local changes.

## Current A-side

- Mandatory signed-in entry flow with the existing Nana launch, onboarding, account, Apple sign-in, consent and profile completion screens.
- Email entry is explicitly local and format-only: any valid email and 8–128 character password can enter without prior registration. Passwords are neither checked against saved credentials nor persisted/sent. This does not verify mailbox ownership.
- Registration and profile completion save details on this device. Local profiles and the active account selection are stored in a device-only Keychain record. Logging out clears the session selection but retains profiles for the next local login.
- Apple entry uses real AuthenticationServices authorization. The returned Apple user ID is isolated from email-only accounts; first-authorization name/email are retained locally, completed profiles are restored on later sign-in, and Apple credential state is checked at launch and foreground return. No Nana backend Token is invented.
- Four custom tabs: Live, Rooms, Messages and Me.
- Published JSON is decoded into `NanaProfile`, `NanaLiveRoom`, `NanaRoomSeat`, `NanaPost`, `NanaConversation`, `NanaMessage`, `NanaGift`, `NanaWalletSnapshot` and related models.
- Published read data is cached per signed-in account. Actions without a published write contract show an unavailable state and do not claim success.
- Pre-recorded stage artwork stands in for live media and a local camera preview stands in for outgoing video-call preview. There is no remote communication in this A-side build.
- Bundled `pics` and `videos` are resolved through local asset keys; unknown keys retain a placeholder.

## Structure

- `NanaHarbor/Features/AccountAccess/` — existing Nana entry flow.
- `NanaHarbor/Features/Home/` — Live feed, search/filter and post detail.
- `NanaHarbor/Features/Gather/` — room list, room creation and room detail.
- `NanaHarbor/Features/Inbox/` — conversations and local video-call state.
- `NanaHarbor/Features/Profile/` — profile, connections, album, wallet, check-in, collection and level surfaces.
- `NanaHarbor/Shared/Models/NanaLiveModels.swift` — business-semantic A-side models.
- `NanaHarbor/Shared/Content/NanaContentStore.swift` — published read repository with local device overlays.
- `NanaContentSnapshot.sample` — development-only fixture compiled under `DEBUG` and enabled only with `-NanaDevelopmentFixtures`.
- `NanaHarbor/Assets.xcassets/` — existing entry artwork plus selected 88-直播3 slices with semantic asset names.

`project.yml` is the XcodeGen source of truth. The Bundle ID is `com.nanalantern.harbortide`. The project does not add B-side WebPortal, H5, StoreKit or realtime dependencies.

## A-side read service

- Platform app: `67746202`; configured HTTPS origin: `https://lantern.party.top`.
- On launch, GET `/harbortide/v1/bootstrap` refreshes the complete baseline. The home, rooms, messages, wallet, search and room detail screens revalidate their matching published read endpoint when opened.
- The client declares all 12 read operations from the exported template, including literal detail routes. No endpoint outside that export is constructed.
- Requests accept JSON, include `nanaReleaseVersion`, and have bounded timeouts. There is no fabricated login Token or server authentication claim. The app's signed-in navigation gate remains independent of these fixed responses.
- On transport, HTTP or decoding failure, the current persisted data remains available and the page exposes a retry state. The repository records a sanitized error; it never stores or prints a raw response.
- The published snapshot persists per account under Application Support/NanaReadCache, with hidden-profile preferences and drafts kept locally. Wallet, gift, follow, moderation, chat, check-in and server profile writes remain unavailable until a real write contract exists. Local profile edits remain on the device. A read-service 401 shows a content error and does not log out the local account.
- Images and videos resolve to bundled files only; server `bundlePath` values are not used as arbitrary filesystem paths.

### Integration status — 2026-09-21

The user confirmed platform publication. The domain purchase status is intentionally ignored for this integration pass; live device decoding and reachability still need user-side verification. No app build or tests were run, as requested.

Apple sign-in requires the developer team's `com.nanalantern.harbortide` App ID and provisioning profile to enable Sign in with Apple. The project already includes the entitlement. Authorization, cancellation, credential revocation and cold-launch restoration still require device verification; this change was reviewed at source level only.
