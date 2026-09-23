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

The USD values are reference prices only; the wallet requests StoreKit localized display prices and shows View price while unavailable. Apple checkout remains authoritative. Coins per reference USD increase with every tier. EXTRA describes additional coins relative to the pack's stated base amount, not a reduction from a fabricated old price.

## Store setup still required

Create `qvntkzplmrxhcad` ($2.99 reference tier) and `bhswqjfvndkztre` ($29.99 reference tier) as consumable products in App Store Connect. This task adds the identifiers to the local catalog only; it does not register or publish products with Apple. Align any external product descriptions with the new coin totals before release. Purchase verification, cancellation and pending handling remain unchanged.

## Artwork

- First price button: original `assets/voice-room-slices/voice_asset_073.png`, including its flame silhouette.
- Other price buttons: the blank capsule body of original `assets/voice-room-slices/voice_asset_043.png`; the lower speech pointer is clipped in the view without changing the source file.
- Bonus tag: original unlettered `assets/voice-room-slices/voice_asset_069.png`. Native percentage and EXTRA labels show the pack's actual bonus. The ring, flower shape, outline and shading all come from the supplied artwork.
- Wallet uses no generated replacement artwork. All original source images are preserved.

Static source, arithmetic and asset inspection only; no compilation, tests, simulator launch or live purchase was performed.

## App Store Connect 填写清单

全部选择 Consumable。以下 USD 是建议配置价格，不是已经核实的 App Store Connect 价格；实际页面和结算使用 Apple 返回的当地价格。显示名称不超过 30 字符，描述不超过 45 字符。参考名称可直接沿用显示名称。

| 显示名称 | 描述 | 商品 ID | USD | 到账金币 |
| --- | --- | --- | ---: | ---: |
| Nana 600 Coins | 600 coins for digital gifts in Nana | xtgkjmjhjxcvxgr | 0.99 | 600 |
| Nana 1300 Coins | 1300 coins for digital gifts in Nana | zezqgkvbircdido | 1.99 | 1300 |
| Nana 2025 Coins | 2025 coins for digital gifts in Nana | qvntkzplmrxhcad | 2.99 | 2025 |
| Nana 3500 Coins | 3500 coins for digital gifts in Nana | npftelsnomirowvr | 4.99 | 3500 |
| Nana 7500 Coins | 7500 coins for digital gifts in Nana | rvkwjwglymgcdhk | 9.99 | 7500 |
| Nana 16000 Coins | 16000 coins for digital gifts in Nana | efmgfwjfueyseizi | 19.99 | 16000 |
| Nana 24750 Coins | 24750 coins for digital gifts in Nana | bhswqjfvndkztre | 29.99 | 24750 |
| Nana 42500 Coins | 42500 coins for digital gifts in Nana | dgedfppvsxndaou | 49.99 | 42500 |
| Nana 90000 Coins | 90000 coins for digital gifts in Nana | kcrboklodxeabcdx | 99.99 | 90000 |

当前仅核实本地代码中的 9 个 ID，未登录 App Store Connect，不能确认它们已创建、定价、配置销售地区或完成提交。首次提交内购需与 App 版本一同提交，并补充实际内购页面截图。请同时确认 Paid Apps 协议、税务及收款资料。

代码使用 StoreKit 2 产品请求及 Apple 交易验证，不会在购买失败时模拟加币。Release 拒绝 Xcode 本地交易，Apple 官方沙盒交易仍可用于审核与 TestFlight；不能将沙盒标识隐藏或改成生产环境。新交易使用持久化 appAccountToken 关联原购买账号，并恢复处理未完成交易。旧版本无账号 Token 的未完成交易无法安全猜测归属，会保留待处理。

金币账本目前保存在本机 Keychain，并非服务端钱包，不具备跨设备余额恢复或服务端退款通知同步。上线前需要对真实商品加载、取消、待批准、验证失败、重新启动及切换账号进行真机沙盒验收。本次遵守项目约定，没有编译或执行购买测试。

参考：
- [内购字段及字符限制](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information)
- [首次内购提交](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- [Apple 沙盒与 Xcode 本地测试的区别](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox)
