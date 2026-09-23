# Nana coin packs

The catalog in `NanaHarbor/Shared/Commerce/NanaCoinStore.swift` is the source of truth. Displayed totals and verified StoreKit credits both use `baseCoins + bonusCoins`; the EXTRA tag uses `bonusPercent`. Existing balances and previously processed transactions are not rewritten.

| USD reference price | Base coins | Extra | Bonus coins | Total credited | Product ID | Status |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| $0.99 | 500 | 20% | 100 | 600 | xtgkjmjhjxcvxgr | Existing ID |
| $1.99 | 1,000 | 30% | 300 | 1,300 | zezqgkvbircdido | Existing ID |
| $2.99 | 1,500 | 35% | 525 | 2,025 | qvntkzplmrxhcad | New ID |
| $4.99 | 2,500 | 40% | 1,000 | 3,500 | npftelsnomirowvr | Existing ID |
| $9.99 | 5,000 | 50% | 2,500 | 7,500 | rvkwjwglymgcdhk | Existing ID |
| $19.99 | 10,000 | 60% | 6,000 | 16,000 | efmgfwjfueyseizi | Existing ID |
| $29.99 | 15,000 | 65% | 9,750 | 24,750 | bhswqjfvndkztre | New ID |
| $49.99 | 25,000 | 70% | 17,500 | 42,500 | dgedfppvsxndaou | Existing ID |
| $99.99 | 50,000 | 80% | 40,000 | 90,000 | kcrboklodxeabcdx | Existing ID |

The USD values are fallback/reference prices; existing StoreKit localized display prices and Apple checkout remain authoritative. Coins per reference USD increase with every tier. EXTRA describes additional coins relative to the pack's stated base amount, not a reduction from a fabricated old price.

## Store setup still required

Create `qvntkzplmrxhcad` ($2.99 reference tier) and `bhswqjfvndkztre` ($29.99 reference tier) as consumable products in App Store Connect. This task adds the identifiers to the local catalog only; it does not register or publish products with Apple. Align any external product descriptions with the new coin totals before release. Purchase verification, cancellation and pending handling remain unchanged.

## Artwork

- First price button: original `assets/voice-room-slices/voice_asset_073.png`, including its flame silhouette.
- Other price buttons: the blank capsule body of original `assets/voice-room-slices/voice_asset_043.png`; the lower speech pointer is clipped in the view without changing the source file.
- Bonus tag: original unlettered `assets/voice-room-slices/voice_asset_069.png`. Native percentage and EXTRA labels show the pack's actual bonus. The ring, flower shape, outline and shading all come from the supplied artwork.
- Wallet uses no generated replacement artwork. All original source images are preserved.

Static source, arithmetic and asset inspection only; no compilation, tests, simulator launch or live purchase was performed.
