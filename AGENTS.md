# Nana working agreements

- Preserve native SwiftUI unless the current requirements justify changing the architecture.
- Do not compile, run, launch a simulator, or execute tests unless the user explicitly requests it. Source and resource inspection is permitted.
- Use descriptive business names for folders, types, fields, and component parameters. Prefer accurate domain language over generic template names or elaborate metaphors. Do not obfuscate code or claim naming guarantees App Review approval.
- Follow the user's supplied screen designs and reuse assets in `assets/photos`; preserve those originals. Inspect each asset for embedded text and logos before adding overlays.
- Backgrounds fill the entire display using aspect fill and ignore safe areas. Keep interactive content reachable when the keyboard is visible.
- Evaluate Taste, Design, and Garden skills before visual changes; use applicable native design/asset guidance without introducing web implementations.
- Keep credentials out of logs and UserDefaults. Do not simulate a successful authentication when only local input validation has passed.
