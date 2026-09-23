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

Wallet refinement follows the supplied reference's compact balance typography, overlapping full-width recharge surface, charcoal rows, larger coin artwork and smaller capsule price controls. The first price control now uses the supplied flame-shaped `voice_asset_073` artwork; the remaining controls are violet. Pink hanging tags show the actual extra-coin percentage and each row states the included bonus. The original seven product identifiers are retained, two tiers are added, and coin totals are recalculated as base plus bonus. See `coin-pack-catalog.md` for all nine tiers and required App Store Connect setup. Existing balances and purchase verification behavior remain unchanged. No fictitious old price or countdown is shown.

Check-in refinement preserves the original 700 × 1238 artwork aspect ratio and positions the hero/calendar content against its binding rings. It uses centered `yyyy/MM` month navigation, complete Monday-first weeks based on each month's actual length, charcoal date cells, a violet progress track and a full-width Clock in capsule. The bottom strip describes the existing free daily reward. Actual check-in dates and the once-per-day 10-point local save remain unchanged; paid check-in and retroactive purchase prices from the mockup are not introduced.

Wallet/check-in asset audit: the wallet's price controls use supplied `voice_asset_073` (flame) and the capsule body of `voice_asset_043` (lower pointer clipped in the view). Bonus tags use the original blank `voice_asset_069` with dynamic, accurate EXTRA percentages. Check-in directly uses `voice_asset_146` (Check-in), `voice_asset_128` (Clock in), `voice_asset_030`/`032` (month arrows), `voice_asset_149` (checked date) and `voice_asset_018` (calendar illustration). Embedded button lettering is not duplicated. Check-in buttons retain disabled state and accessibility labels after completion. No generated replacement artwork is used on these two screens; original PNG files are unchanged.

## Original daily check-in guide

The check-in help entry now presents `NanaAccountGuide` with the check-in topic, an in-page modal with original raster artwork instead of the shared system sheet. Original assets created with the built-in image-generation tool are `NanaCheckInGuideSurface` (satin aubergine panel), `NanaCheckInGuideCalendar` (ceramic calendar, rose seal and activity crystals), and `NanaCheckInGuideButton` (blank violet enamel action). All are project-local imagesets under `NanaHarbor/Assets.xcassets`; full prompts are in `garden-gpt-image-2/prompt/nana-check-in-guide-20260923.json`. Existing supplied wallet/check-in artwork is preserved.

Design guidance follows Claude Design reference/context and hierarchy rules. Taste/web implementation workflows were evaluated as outside this native SwiftUI scope. Garden `gpt-image-2` Host-Native and the imagegen skill guided original raster production. The guide uses no SF Symbols, system sheet chrome, code-drawn card, decorative path, or code-drawn button. Native text/layout and a dimming scrim remain native for legibility and interaction.

The copy reflects the implementation: free once-daily +10 activity points, one level per 200 points, device-local calendar date, no retroactive claims, account-scoped device storage. It distinguishes activity points from wallet coins. The scrollable content and persistent 64pt dismiss target accommodate small screens and larger text. Outside-tap and accessibility escape dismiss the guide; the underlying page is hidden from accessibility while it is open. Asset/alpha, source and diff checks only; no build, tests, launch or simulator verification.

## Original Messages empty-state illustrations

The two Messages empty states use newly generated Nana artwork instead of system-symbol tiles. `NanaEmptyFriendsLive` is a lavender miniature camera and ivory speech bubble; `NanaEmptyConversations` is a pair of sculptural speech bubbles with a violet connecting ribbon. Both are transparent PNGs with no baked-in text. Original generation used the host-native image tool, guided by Garden `gpt-image-2` and the imagegen skill; the full prompt specifications are saved in `garden-gpt-image-2/prompt/nana-empty-*-20260923.json`. No downloaded stock art or existing mascot was used as input.

The friends state is a compact horizontal card with a View friends action. The conversation state uses centered artwork, shorter explanatory copy and a Find people action leading to search. Artwork is decorative for VoiceOver; text scales, and the live card switches to a vertical layout at accessibility text sizes. The existing real-data empty conditions and populated lists are preserved. Asset transparency, catalog registration and diff formatting were inspected without building or launching the app.

## Original wallet guide

Wallet help now shares the original illustrated `NanaAccountGuide` modal with check-in, using its own title, subtitle, rules and hero. `NanaWalletGuideIllustration.imageset` contains a new original lilac coin purse, gold coins and ivory gift illustration generated with the built-in image tool. The full prompt is `garden-gpt-image-2/prompt/nana-wallet-guide-20260923.txt`. The original guide panel and image button are reused; no system sheet chrome, SF Symbols or code-drawn decorative artwork is used.

Wallet rules explain room gifts and free gifts, included bonus coins and EXTRA percentages, App Store checkout pricing, verified credit and pending confirmation. The footer distinguishes coins from activity points. The shared component preserves check-in content, scrolling, the persistent dismiss action, outside-tap dismissal and accessibility escape. Recharge products, amounts and purchase handling are unchanged in this revision. Source/resource/alpha checks only; no build, tests, app launch or simulator verification.

## Store reference refinement

Store now follows the supplied four-column layout: two priced tile rows followed by two rows of standalone artwork for the same eight gifts. Both presentations select the same catalog item; no duplicate products or invented prices are introduced. Supplied tile PNGs, selection plate 131, quantity controls 116/117, coin 110 and Buy button 169 replace reconstructed controls. The Buy artwork has a fixed 56pt width, so its embedded word cannot wrap. The bottom balance/control bar uses the original generated `NanaStoreCheckoutSurface` raster, created with the built-in image tool; prompt: `garden-gpt-image-2/prompt/nana-store-checkout-bar-20260923.txt`. Transparent export margins are clipped only in the view.

Store, profile, wallet and room gifts continue observing the single session-scoped NanaCoinStore injected by NanaEntryCoordinator. No separate balance or server refresh overwrite was added. Verified recharge credit now persists the updated ledger and transaction ID before publishing a changed balance, matching the existing durable room-gift debit pattern; a save failure leaves the previous balance visible and the transaction unfinished for retry. Store inventory purchasing remains its existing unavailable action; this visual revision does not fabricate a purchase or deduct coins without granting inventory. Source/resource checks only; no build, tests or simulator launch.

## Settings details — original artwork and working controls

The five destinations highlighted in Settings now use full-screen native SwiftUI pages with concise introductions, original ceramic illustrations, image-backed aubergine cards and violet image buttons. `NanaSettingsSecurity`, `NanaSettingsAccounts`, `NanaSettingsPrivacy`, `NanaSettingsNotifications` and `NanaSettingsStorage` are original transparent raster images generated with the host-native image tool. Prompts are preserved in `garden-gpt-image-2/prompt/nana-settings-details-20260923.json`. The shared card surface reuses the original Nana check-in guide panel, registered at 3× with preserved corner insets; the original guide button is reused. Supplied source artwork is untouched. Claude Design's native hierarchy guidance and Garden/imagegen asset guidance apply; Taste and browser implementation skills were evaluated as outside this native scope.

- Account security shows the current sign-in method, concealed/revealable email, a device-only clipboard copy expiring after two minutes, profile editing and real Apple credential-state checking. Local email profiles are not represented as verified mailboxes; remote password/session operations remain unavailable.
- Accounts lists saved profiles, identifies the current account and confirms departure before continuing to sign-in. Selection only prefills an email; it does not authenticate or automatically activate a saved profile. Account data and balances remain isolated.
- Privacy provides saved, working controls for hiding balances across profile/wallet/store/room gifts, concealing the account email on entry and pausing the featured-room carousel. Hidden balances are also removed from combined accessibility labels. Blocked-account management and the iOS permission page are reachable. Failed preference writes retain the previous value and display a notice.
- Notifications reads actual iOS permission and can request it or open system settings. A separately saved opt-in schedules a real local daily check-in reminder at 20:00 device time. The reminder is removed/reconfigured as the active account changes and contains no private account details. It is not a remote message/live-room push service.
- Storage shows actual downloaded-content file size and URLCache memory/disk usage, supports refresh and confirms cache removal. Video-preview memory is cleared too, with its exclusion from the byte count stated. Already displayed content remains available; photos, personal state and coins are not deleted.

Validation was limited to source/data-flow review, asset catalog JSON/file/PNG-alpha inspection and `git diff --check`. No compilation, tests, app launch or simulator review was performed, as required by this project.

## Settings safety, policies and account exit

Settings now exposes Blocked accounts directly. The list reads only the active account’s persisted `personal.hiddenProfiles`; no suggested/sample accounts populate it. Each stored user has an explicit Unblock action, which persists before removing the row and reporting success. Empty, error and success states are visible. Separate reports are preserved when unblocking. The page reuses the original privacy illustration and raster card/button system.

User Agreement and Privacy Policy in Settings and About Us use exactly the same `AccountPolicyDocument` addresses and `AccountPolicyBrowser` as the login/welcome pages. No Contact Us action is presented. The previous About Us help destination is replaced by Community Guidelines, also linked directly from Settings. The new scrollable native page covers respectful conversation, prohibited content and child safety, recording/privacy, responsible hosting, media rights, voluntary gifts, scams/spam, reporting/blocking and consequences. It explicitly describes the current local-only report storage rather than promising live moderation that does not exist.

Policy drafting references reviewed on September 23, 2026: [Apple App Review Guidelines, sections 1.1 and 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content) and [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/). Published contact information, filtering, an operational reporting/review service and server-side account deletion/Apple token revocation remain service requirements; displaying rules is not a substitute for those capabilities or a guarantee of review approval.

Logout and local-account deletion use the original-image confirmation/progress UI, block repeat actions, show success only after protected storage writes complete and then navigate explicitly: logout → login; deletion → welcome. Logout preserves account data. Local deletion removes the selected profile and Apple introduction from the local membership ledger, its avatar, account-specific personal directory (including album photos), read cache and wallet entry. Other accounts remain saved. Unlinked completed StoreKit transaction IDs are retained to prevent duplicate credit; no deleted profile identifier is retained with those IDs. A purchase in progress prevents account exit. Storage failures report failure rather than success; partially removed data can be retried. Daily local reminders are canceled on successful exit.

The current project has no authenticated remote account deletion or Apple token revocation endpoint. Confirmation and success copy identify this operation as local account deletion; it is not represented as full service deletion. Static source/resource/diff inspection only; no build, tests, app launch or simulator execution.

## Profile editor layout repair

The editor now places its full-width Save changes bar inside the form ScrollView's bottom safe-area inset, rather than attaching an intrinsic-width button outside the page's NavigationStack. The scrollable fields reserve footer space and keep keyboard avoidance active. Focus moves from nickname to country to introduction, with an explicit Done typing control while editing.

The original `NanaSettingsCardSurface` and `NanaCheckInGuideButton` artwork provide consistent form groups and controls. Photo selection/reset is presented with clear text actions beside the existing account portrait. Basic details, gender, interests and introduction are separated; field labels and prompts have stronger contrast. Interest/gender targets are at least 48pt high, wrap long labels and become one column at accessibility text sizes. The introduction supports three to five visible lines and a live 160-character count. Existing account-scoped load/save and protected photo import remain intact.

The birthday destination uses the same native page and original image controls, with independently scrollable year/month/day columns and an explicit commit action. Calendar month lengths, leap days and future-date rejection are handled without applying a selection when the user goes back. No new system-symbol decorations or generated replacement assets were added. Claude Design's hierarchy guidance and Garden's original-asset reuse guidance remain applicable; browser-only Taste/implementation workflows remain outside this native scope. Source/resource and diff inspection only; no compilation, tests, simulator or app launch.

## Ranking account identity consistency

The personal ranking footer now uses `NanaAccountAvatarView`, matching My Profile for both uploaded photos and the existing supplied default portrait. Its displayed name observes `NanaSessionStore.activeProfile`, and its level reads the same `NanaContentStore.activityLevel` as My Profile. Published ranking rows marked `isCurrentUser` use these same live account values instead of stale response identity fields, and do not open an unrelated public-profile snapshot. Rank and gift counts remain independently sourced from the ranking response; unknown values are not invented. This is a data-binding/component-reuse correction with no new artwork or visual redesign. Static source/diff review only, without building or running the app.

## Comment report and block actions

Other users’ comments now expose separate Report and Block buttons in both the video/post comments sheet and inline post responses. The new controls reuse the original Nana image button, provide 44pt targets and accessible author-specific labels, and adapt to narrow layouts. Self-authored comments omit these actions and display the latest local account name/photo. Safety selection is owned by the parent screen, so hiding a row does not remove its confirmation flow.

Comment reports use a dedicated `comment` content kind and a hashed, parent-scoped comment key. The account-local record includes the parent key, comment ID, author ID, reason, bounded text excerpt and date. Hidden comment keys are separate from hidden posts, so reporting one comment leaves the parent post/video available. Blocking uses the existing persisted author blacklist, filters that author’s comments across discussions and supports the existing Unblock action. Unblocking does not undo independently reported comments. New persistence fields are optional for older saved data. Empty lists and save failures remain visible; comments no longer jump to the bottom when moderation removes rows.

The existing safety sheet is reused and identifies comment targets with author/text context. Report feedback explicitly states device-local storage and does not imply remote moderation delivery. Claude Design/Garden asset reuse guidance applies; no new decorative system icon or raster generation was required. Source/data-flow and `git diff --check` inspection only; no build, tests, app launch or simulator execution.

## Video creator profile navigation

The video detail author image and name now form one accessible profile button with a minimum 44pt target. Linked authors open the existing member profile. Creators without a service profile open a native creator page using the supplied identity/cover and only visible videos with the same discussion author ID; unknown biography, relationship counts and levels are omitted. This page reuses the existing background, detail header, media previews and report/block flow, without new artwork or fabricated member records.

Presenting the profile pauses the underlying player immediately. Closing it resumes only when the scene is active, other overlays are closed and the user had not manually paused. The profile uses a sheet so ordinary dismissal preserves the playback position. Blocking the creator continues to dismiss hidden content through the shared safety state. Claude Design/Garden asset reuse guidance applies; browser-oriented Taste workflows remain outside this native navigation change. Static source/diff inspection only; no compilation, tests or simulator execution.

## Room profile, explicit follows and message entry

The room host information card's portrait/name opens the matching native member profile. Room and conversation statistics now say Follower and Following. The supplied replay cast uses stable small follower/following pairs: Ava 128/36, Jules 76/29, Mira 93/41, Noah 164/58, Lin 47/23 and Sienna 62/34. These counts are applied only to replay hosts (and the bundled development fixtures), never authenticated relationship records. Shared profile data keeps room, member and chat displays consistent through catalog refreshes.

Public profile/room follow flags no longer establish account relationships. A fresh account follows nobody; local explicit choices and authenticated mutual relationships are the only follow sources. The Ava fixture's default flags are false. Existing intentional choices survive refresh/relaunch. Mutual friends require both an outgoing follow and an incoming follow from the account-specific inbox; blocking still excludes that person.

Room, profile and friend-list message actions open the existing conversation or an empty, stable draft composer. Opening it does not follow a user or add a fake inbox entry. Sending checks the current account, block state and mutual follow at that moment; rejection retains the draft. Authenticated delivery remains unavailable in the current read-only service and is reported honestly after the relationship check, without fabricated sent messages. Native components and original supplied artwork are reused under the existing Claude Design/Garden guidance; no new visual assets were needed. Source/diff inspection only, with no build, tests or simulator launch.

## Staggered local welcome followers

Each account receives one persisted welcome plan of one to three distinct supplied replay profiles, randomly chosen after the public catalog and protected account storage are ready. The first arrival waits 15–35 foreground seconds; subsequent arrivals each wait another 40–90 seconds. Backgrounding, account exit, account switching and deletion cancel the active timer. On return, the pending arrival restarts its own delay instead of delivering overdue entries together. Completed entries persist across ordinary logout and relaunch; refreshing catalog data never rerolls or duplicates the plan. Blocked or already-arrived candidates are skipped, and write failure never publishes an arrival.

These are explicitly labeled local simulated welcome interactions in the new-followers list, relationship list and member profile. They update the local follower count but do not write outgoing follows, create messages, populate live friend rooms or satisfy authenticated mutual-follow checks. Real inbox records take precedence when the same identity is supplied later. Local account deletion removes the plan with the rest of personal data. Existing native typography/components are reused; no new artwork. Verification was limited to source/data-flow review and diff whitespace checks, without builds, tests, app launch or simulated elapsed-time execution.

## Single entry for report and block

Video details, post details, comments, member profiles, bundled creator profiles and voice member cards now use one More button (`NanaSafetyOptionsButton`) instead of exposing Report and Block directly. The 44pt control reuses the original `NanaCheckInGuideButton` artwork and opens the existing safety sheet on its options page. Users then choose Report or Block and proceed through the existing reason/confirmation flow. Self-authored comments continue to omit moderation actions.

The conversation header's existing more button opens that same options page directly, eliminating the redundant intermediate menu. Rooms already place Report and Block inside their Room options menu and retain that flow. Video playback continues to pause while its safety sheet is open. Claude Design/Garden asset reuse guidance applies; no new icons or illustrations were introduced. Static source and diff checks only; no build, tests or simulator launch.

## Reference-led public member profiles

Public member and bundled creator pages now share `NanaUserProfileView`. Room, voice-seat, ranking, search, friends, chat and video-author destinations present the page full screen. A full-width photo hero carries the name, available metadata, small relationship counts and original Follow control near its lower edge, followed by a black content area, an available host-room card and Posts / Photo album tabs. A fixed safe-area footer uses the supplied Chat (`voice_asset_152`) and Start video (`145`) artwork in their original 260:414 width ratio, with embedded text left intact. Follow (`100`/`101`), more (`119`), back (`030`), room card (`042`) and photo-like (`098`/`167`) artwork are also reused. No decorative system symbols or generated replacement art were added.

Posts and video tiles filter by the displayed author ID. Optional `publicPhotoAssetKeys` provides published photo data; absent data shows an honest empty album and never exposes the signed-in account's private photos. Photo previews support swipe paging, page count, local likes, explicit follow and the existing More moderation menu. Previewing the profile cover is separate from inventing album entries. Creator-only records carry an optional `hasCompleteDetails = false`, hiding unknown statistics/age rather than fabricating them. Explicit follows can persist these known creator identities, and chat receives that identity even before following. All original outgoing-follow and send-time mutual checks remain intact. Video calls still show the existing unavailable-service state; the UI does not claim a call transport exists.

The berniemor creator photo uses a clear frame at three seconds from the supplied video, stored separately in `videos/portraits/berniemor_DddsSyxCRiE.jpg`; original videos and covers remain unchanged. The clip's embedded caption is preserved. The already-bundled videos folder includes the new subfolder. Opening a full-screen author page pauses and retains the underlying video player; returning resumes according to the prior manual playback choice instead of reloading a stopped player.

Claude Design's reference, typography and hierarchy guidance and Garden's supplied-asset audit were applied; Taste/browser-specific implementation workflows were evaluated as outside this native SwiftUI scope. Asset contact sheets and the extracted source frame were visually inspected. Source/resource wiring and `git diff --check` passed; no compilation, tests, app launch, simulator or rendered UI verification was performed.

## Public profile portrait and proportion correction

The user explicitly approved existing supplied person photographs as sample avatars for video creators that have no corresponding profile portrait. All 17 bundled creator handles now have a fixed `nana.pic` mapping. Existing genuine profile avatars take precedence; missing avatars and previously saved video-cover avatars resolve through the same mapping in public profiles, video author buttons, followed/blocked identities and conversation headers. This mapping is independent of clip order and never establishes a follow relationship. Video assets continue to use video covers for media previews; the earlier extracted berniemor frame is no longer used as an avatar override.

The profile hero now prioritizes the avatar and uses an explicit screen-width frame and a bounded 1.34 width-to-height proportion, with smaller identity typography and compact original Follow artwork. The portrait preview starts on the actual tapped avatar. Content follows immediately: a hosted-room card or explicitly labeled recommendation from the visible room catalog, compact tabs, full-width video posts and two-column public photos. Category chips come from available posts/hosted rooms; creator-only records retain unknown age/counts/biography rather than fabricated details. The supplied Chat and Start video artwork floats above a bottom fade, and scroll padding keeps the last content reachable.

Native SwiftUI and supplied raster controls remain in use under the previously evaluated Claude Design/Garden guidance. Static resource inspection found a valid existing photo for every bundled creator, and `git diff --check` passed. No build, tests, app/simulator launch or rendered-screen verification was performed, per the project working agreement.

## Public album routing and photo detail

Profile post photos now have their own photo-viewer action; only the separate title/body action opens the text post and comments. The public album combines the profile's published photo keys with that author's visible, non-video post photos, removing duplicate and missing assets. It never reads private account photos or invents album entries. Tapping a thumbnail preserves its starting index and the viewer's complete photo sequence.

The photo viewer uses full-screen aspect-fill photos, centered real page counts, swipe paging, compact position indicators, original pink like artwork (`098`/`167`), original wide Follow/Followed artwork (`137`/`150`) and top-right More. Bottom controls float over the photo without a solid footer. Likes remain local per account/author/photo; follow state uses the shared explicit-follow store. No gift entry or fabricated like total is shown. Existing Claude Design/Garden native design and supplied-asset guidance applies. Source and diff checks only; no build, tests or simulator launch.
