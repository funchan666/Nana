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

`project.yml` is the XcodeGen source of truth. The Bundle ID is `com.nanalantern.harbortide`. The project does not add B-side WebPortal, H5 or realtime dependencies. Coin purchases use the native StoreKit 2 framework; see [coin pack catalog](docs/coin-pack-catalog.md) for product setup.

## A-side read service

### Bundled video collection

All 17 supplied MP4 files in `videos` are included in the default home recommendation feed. Videos already represented by room cards are not added again; other bundled videos use video cards without invented room metadata. Following/category filters still apply to room content. Room refresh failures remain visible while bundled videos can be watched.

Each card uses the matching first decoded frame from `videos/covers`, centered and cropped to fill its bounds. Covers are bundled, so scrolling does not start video players or extract frames on the main thread. Tapping a video opens a single player; dismissal or backgrounding pauses playback. Run `python3 scripts/generate_video_covers.py` after adding or replacing videos (requires FFmpeg). Original videos are preserved.

### Published endpoints

- Platform app: `67746202`; main domain: `https://nanacc.top`; configured API HTTPS origin: `https://lantern.nanacc.top`.
- On launch, GET `/harbortide/v1/bootstrap` refreshes the complete public baseline. The home, rooms, wallet, search and room detail screens revalidate their matching published read endpoint when opened. Messages does not treat the public conversation examples as an account inbox.
- The client declares all 12 read operations from the exported template, including literal detail routes. No endpoint outside that export is constructed.
- Requests accept JSON, include `nanaReleaseVersion`, and have bounded timeouts. There is no fabricated login Token or server authentication claim. The app's signed-in navigation gate remains independent of these fixed responses.
- On transport, HTTP or decoding failure, the current persisted data remains available and the page exposes a retry state. The repository records a sanitized error; it never stores or prints a raw response.
- The published snapshot persists per account under Application Support/NanaReadCache, with hidden-profile preferences and drafts kept locally. Wallet, gift, follow, moderation, chat, check-in and server profile writes remain unavailable until a real write contract exists. Local profile edits remain on the device. A read-service 401 shows a content error and does not log out the local account.
- Images and videos resolve to bundled files only; server `bundlePath` values are not used as arbitrary filesystem paths.

### Integration status — 2026-09-22

The user confirmed platform publication and supplied the new main and API domains. The platform screenshot marks the main domain as active. The A-side client now uses `https://lantern.nanacc.top`, preserving all published paths, methods and fields. The main domain is recorded here; the current A-side app has no separate main-domain consumer. Live device decoding and reachability still need verification. No app build or tests were run, as requested.

Apple sign-in requires the developer team's `com.nanalantern.harbortide` App ID and provisioning profile to enable Sign in with Apple. The project already includes the entitlement. Authorization, cancellation, credential revocation and cold-launch restoration still require device verification; this change was reviewed at source level only.

### Account inbox

Messages renders only `NanaAccountInboxSnapshot`, separate from the public bootstrap, anonymous conversation endpoint and their cached examples. The published contract currently supplies neither authenticated private messages nor confirmed mutual-follow relationships, so the inbox starts empty. A future authenticated messaging integration must pass its account-specific snapshot to `replaceAccountInbox`; no endpoint or successful delivery is invented here. Switching accounts or signing out clears the private snapshot.

The friend rail requires confirmed mutual friendship and an active live room, excludes bundled replays and locally unfollowed/hidden authors, and shows each host once. Tapping a friend opens the room. Conversations and message bodies share the private source and retain local hide/block/read handling. Each section has its own empty state; anonymous catalog refreshes and old cached examples cannot populate either section. These changes were inspected statically without building, running or testing the app.

## Release preparation

See [release readiness record](docs/release-readiness.md) for resource sizes and outstanding service requirements, [App Store metadata](docs/app-store-metadata.md) for accurate listing copy, and [coin pack catalog](docs/coin-pack-catalog.md) for all nine IAP entries. Real review credentials and App Store Connect product availability remain unverified.

Development documents and resource inventories live in [docs](docs/README.md). README.md and AGENTS.md stay at the project root. Documentation and scripts are not application resources.

Before distribution, run the read-only [release resource audit](docs/release-resource-audit.md) against the exported App or IPA. This checks the artifact without building or launching the app.
