# Third-party notices

Brighter is distributed under GPL-3.0-only. The single-point EDR trigger and gamma-table approach are based on BrightIntosh by Niklas Rousset and contributors, also GPL-3.0. Brighter is an independent app and is not endorsed by its authors.

- BrightIntosh: https://github.com/niklasr22/BrightIntosh
- Source reviewed: `15892f27ba11d2c5bca9f7d0c237b02541a45d90`
- Reference files: `OverlayWindow.swift`, `UI/Overlay.swift`, `GammaTechnique.swift`, `Utils.swift`.
- Original notices: OverlayWindow created by Niklas Rousset on 13.07.23; Overlay created by Niklas Rousset on 12.07.23.
- Changes: independent Russian menu UI, bounded gamma policy, optional native maximum control, original brightness restoration, finite gamma validation, small-window invariant and standalone build/tests. Store, licensing, telemetry and other app infrastructure are not incorporated.

BrightXDR by Dmitry Starkov was reviewed to identify the full-screen multiply-blend approach and its documented Spaces limitation; its full-screen renderer is not included.

- https://github.com/starkdmi/BrightXDR
- Source reviewed: `17b70ea34ed4ce8fadd87e7baacee72aac2e61ac`

Apple frameworks and SF Symbols are supplied by macOS, not redistributed with this source tree.
