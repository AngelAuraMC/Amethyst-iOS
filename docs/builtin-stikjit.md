# Built-in StikJIT

Amethyst can run StikJIT in a bundled classic app extension. The host remains
Objective-C and keeps its iOS 14 deployment target; only the helper loads Swift
and StikJIT, and its minimum OS is iOS 17.4.

## Using it with SideStore

1. Install the IPA directly with SideStore and keep app extensions. Enable
   Developer Mode. The app must be signed with `get-task-allow`.
2. Install/connect LocalDevVPN and obtain this device's **remote pairing file**,
   following the [StikDebug pairing guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md).
3. Open **Settings → JIT setup**, import the file, and select **Built-in StikJIT**.
4. Optionally select **Prepare JIT** to check connectivity and prepare the DDI.
   Launching a game or JAR also performs preparation automatically.
5. Start the game. The helper prepares the DDI, attaches to Amethyst's current
   PID, and runs the app's existing Universal JIT script where required.

Use Wi-Fi when available. If the loopback tunnel is unreachable over cellular,
temporarily disable cellular data while enabling JIT. Following an OS update,
**Reset Developer Disk Image** removes the helper's DDI cache so preparation can
download it again. A reset is a cache operation, not confirmation that the DDI
is mounted or JIT enabled.

This integration imports pairing files; it does not generate them on the phone
or manage VPN settings. Built-in JIT is disabled in LiveContainer, simulators,
and non-iOS device targets in this implementation. The external JIT tool and
wait-for-debugger methods remain available. Existing installations retain the
external method until the user selects built-in JIT.

## Building

On macOS, initialize submodules and use the project's existing JDK 8/native
build prerequisites. StikJIT 2.0.1 recommends **Xcode 27.1 or newer** because of
its generated Swift interfaces.

```sh
git submodule update --init --recursive
gmake -j4 dsym package PLATFORM=2 BUILTIN_STIKJIT=1
```

`BUILTIN_STIKJIT` defaults to `1` for iOS device builds on macOS, and `0`
elsewhere. Use `BUILTIN_STIKJIT=0` to build with the earlier toolchain or without
the helper. This removes any previously embedded helper and StikJIT framework
from the staging bundle. The helper is not platform-patched into simulator,
tvOS, or Catalyst builds.

`scripts/build-stikjit-helper.sh` downloads a pinned XCFramework into the ignored
`depends/stikjit/2.0.1` cache, verifies its SHA-256 before extraction, compiles
the helper, and copies Swift runtime dependencies. It derives the helper's
bundle ID and versions from the built host's Info.plist. The final layout is:

```text
AngelAuraAmethyst.app/
  Frameworks/StikJIT.framework/
  Frameworks/libswift*.dylib          (when required by swift-stdlib-tool)
  PlugIns/AmethystJITHelper.appex/
    AmethystJITHelper
    Info.plist
```

SideStore must re-sign the helper and framework as well as the host. The host
reads the helper's installed bundle identifier rather than assuming that the
original identifier survives re-signing. The existing manual `make codesign`
path is not a substitute for provisioning this extension; use SideStore to
install this IPA, or supply appropriate extension provisioning in your own
signing pipeline.

## GitHub Actions

The **Development build** workflow runs on pushes and pull requests, including
new commits to an existing pull request. It can also be started manually:

1. Commit and push all changes, including `JITHelper`, `scripts`, `tests`, and
   `.github/workflows`. Enable Actions in the fork if GitHub has disabled them.
2. Open **Actions → Development build → Run workflow** and select the branch.
3. After a successful run, download the `org.angelauramc.amethyst-ios.ipa`
   artifact and extract the IPA from its ZIP wrapper.
4. Install the IPA directly using SideStore and keep app extensions. Continue
   with the pairing-file setup above.

The shared `build.yml` job uses GitHub's hosted **`xcode-27`** ARM64 image and
selects **Xcode 27.1**. It installs Zulu JDK 8, GNU make, `ldid`, and CMake
3.31.10. No self-hosted Mac, Apple developer certificate secret, or manual
dependency setup is required. The image is currently a
[public preview](https://github.com/actions/runner-images/issues/14404), so its
availability and installed Xcode versions are controlled by GitHub.

iOS builds explicitly set `BUILTIN_STIKJIT=1`. Both the full and slimmed IPA,
their TrollStore variants, and debug symbols are uploaded. The full IPA includes
Java 8, 17, 21, and 25; slimmed packages require runtimes to be installed
separately. SideStore users should choose the regular full IPA artifact above.
The helper's Debug dSYM is uploaded separately and excluded from the extension;
debug-symbol binaries cannot be recursively signed as executable code.
The manually triggered **Release build** reuses the same job with `RELEASE=1`
and retains the iOS, tvOS, and simulator matrix. Only the iOS device packages
embed the helper.

CI fixes the host bundle identifier to the literal
`org.angelauramc.amethyst.95J8WZ4TN8` before compilation, matching the existing
upstream Debug IPA. The helper inherits this identifier with `.JITHelper`
appended. The suffix is part of the app's installation identity, independent
of the account used to sign it; it is not used as the CI signing team.
Development and Release builds use the same identifier, and artifact filenames
remain unchanged. Package validation rejects any output that loses this
identifier. SideStore must use the same signing account as the existing app
when installing an update.

CI runs the packaging smoke tests before compilation. After packaging,
`scripts/verify-ci-packages.py` checks every expected archive, its runtime
variant, helper executable and metadata, and the StikJIT framework. Missing or
incomplete packages fail the job before upload. JRE directories and the pinned
framework archive are cached; the StikJIT checksum is still checked on cache
hits. The IPA is prepared for re-signing during installation with SideStore.

Local smoke tests and workflow linting do not establish a successful macOS
build or device compatibility. The workflow must complete on GitHub and the
resulting IPA still needs the device validation described below.

## Process lifetime and credentials

The host sends property-list-compatible request values through `NSExtension`.
Its coordinator retains the request after debugger attachment: `enableJIT`
does not return until the script detaches, which may be after JVM setup or,
with "Keep attached" enabled, at the end of the session. Waiting for that
return before launching Java would deadlock. The readiness callback instead
uses Amethyst's existing JIT detection; the existing Java launcher then
performs the executable-memory breakpoint protocol.

Only one helper operation runs at a time. Errors, helper interruptions,
cancellation, or a ten-minute startup deadline clear the pending operation
without starting Java or changing JIT methods. The startup deadline stops
applying once the debugger is ready. Preparation results are informational;
every game launch checks the current process again.

The imported remote pairing file is stored with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in the host's Keychain. It is not
written into Documents. Each request passes its bytes to the helper, which
writes a protected temporary file and deletes it when the operation returns.
Temporary records left by a cancelled or crashed helper are removed at its
next request.
The helper keeps only the DDI cache persistently. Request payloads and pairing
contents are not logged.

## Dependency and validation

- [StikJIT 2.0.1](https://github.com/StikDebug/StikJIT/tree/2.0.1), MPL-2.0.
- Release archive SHA-256:
  `c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95`.
- StikJIT bundles idevice (MIT); notices are in the app's `licenses` resources.
- Architecture/API reference:
  [upstream integration guide](https://github.com/StikDebug/StikJIT/blob/2.0.1/INTEGRATION.md).

The packaging smoke tests run with `python -m unittest discover -s tests -v`
and Bash. They use toolchain doubles to check archive rejection, helper
metadata, runpaths, Swift-runtime staging, and the SideStore package layout;
they do not compile or execute iOS code.

Before distributing, build on macOS and validate on a directly SideStore-signed
device: import a remote pairing file, prepare the DDI, start a vanilla game,
retry after a VPN/pairing error, cancel a pending attempt, relaunch after a
device reboot, and exercise the "Keep attached" setting. iOS 27 behavior and
extension provisioning require that device validation.
