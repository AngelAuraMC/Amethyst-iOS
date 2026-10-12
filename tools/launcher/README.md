# Launcher UI regression checks

Run on macOS with Xcode and an installed iOS simulator runtime. Initialize the pinned AFNetworking submodule first:

```sh
git submodule update --init Natives/external/AFNetworking
python3 tools/launcher/test-ui.py --landscape
python3 tools/launcher/test-ui.py --device 'iPhone 17' --output /tmp/amethyst-launcher-iphone
```

Use `--device` to select another installed simulator device type. `--dependency-root` can point to another checkout with the same pinned AFNetworking revision. Reports and screenshots are written to `--output`; the temporary simulator and app are removed after each run.

The harness compiles the production menu, split controller, account list and skin loader. It stubs unrelated launcher services and supplies deterministic responses for the official profile and texture endpoints. Checks cover navigation items, both account title lines, skin face/hat rendering, legacy skins, caching, offline fallback, and late downloads after account changes or cell reuse. The sidebar check verifies hit testing and the primary-column action; it does not synthesize a tap on UIKit's internal control.

To reproduce the previous navigation item and clipped title, run:

```sh
python3 tools/launcher/test-ui.py --landscape --baseline --baseline-ref origin/main --output /tmp/amethyst-launcher-baseline
```

Keep simulator reports and generated screenshots out of commits.
