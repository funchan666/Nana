# Nana

Nana is a SwiftUI iOS 17 live-room social prototype. The A-side currently follows the purple `88-直播3` direction from the Lanhu reference and uses a typed local Mock source.

## Current A-side

- Mandatory signed-in entry flow with the existing Nana launch, onboarding, account, Apple sign-in, consent and profile completion screens.
- Four custom tabs: Live, Rooms, Messages and Me.
- Local JSON seed data decoded into `NanaProfile`, `NanaLiveRoom`, `NanaRoomSeat`, `NanaPost`, `NanaConversation`, `NanaMessage`, `NanaGift`, `NanaWalletSnapshot` and related models.
- Local mutation overlay persists connection state, room moderation actions, chat, mock gifts, check-in and wallet activity.
- Pre-recorded stage artwork stands in for live media and a local camera preview stands in for outgoing video-call preview. There is no remote communication in this A-side build.
- Placeholder portraits and cover surfaces are intentional until the final media set is supplied.

## Structure

- `NanaHarbor/Features/AccountAccess/` — existing Nana entry flow.
- `NanaHarbor/Features/Home/` — Live feed, search/filter and post detail.
- `NanaHarbor/Features/Gather/` — room list, room creation and room detail.
- `NanaHarbor/Features/Inbox/` — conversations and local video-call state.
- `NanaHarbor/Features/Profile/` — profile, connections, album, wallet, check-in, collection and level surfaces.
- `NanaHarbor/Shared/Models/NanaLiveModels.swift` — business-semantic A-side models.
- `NanaHarbor/Shared/MockData/NanaMockStore.swift` — local read/write Mock repository.
- `NanaHarbor/Shared/MockData/NanaMockPayload.json` — fixed JSON seed.
- `NanaHarbor/Assets.xcassets/` — existing entry artwork plus selected 88-直播3 slices with semantic asset names.

`project.yml` is the XcodeGen source of truth. The project intentionally does not include B-side WebPortal, hnopen, H5, StoreKit or realtime dependencies.
