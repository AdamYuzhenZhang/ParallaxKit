# Sharing and publishing

Repository: [AdamYuzhenZhang/ParallaxKit](https://github.com/AdamYuzhenZhang/ParallaxKit).
Development uses the `main` branch; no stable version is declared yet.

The `ParallaxKit` directory is the standalone repository root. Share this whole
directory, not the surrounding AmbientLab workspace. No package source imports
AmbientLab, ARHandKit, or TextureMonitor. The iOS demo resolves the root package
by a relative path. The demo's third-person inspector illustrates the geometry
using the package's actual camera output.

## Repository contents

- `Package.swift`, `Sources/`, and `Tests/`: Swift products and core tests.
- `Examples/ParallaxKitDemo/`: independent iOS consumer with a shared Xcode scheme.
- `README.md` and `Documentation/`: onboarding and integration.
- `LICENSE` and `THIRD_PARTY_NOTICES.md`: MIT license and original Unity attribution.

Build products, test results, Xcode user settings, and local signing configuration
are ignored. Keep the shared Xcode scheme and the signing example file.
A clone builds in Simulator without a development team; a contributor supplies
their own ignored `Signing.local.xcconfig` for hardware installation.

## Before a release

1. Run the local tests and unsigned device/Simulator builds listed in the
   [README](../README.md). This repository does not run automatic GitHub Actions.
2. Complete the [physical validation checklist](../Examples/ParallaxKitDemo/README.md)
   for the device/OS combinations you intend to support.
3. Keep the [TheParallaxView reference](https://github.com/algomystic/TheParallaxView)
   and full original MIT notice. Do not add its separately licensed artwork.
4. Use semantic-version tags for Swift Package Manager releases once the API is
   ready for versioned consumption, and update the README installation steps to
   name the supported release. Until then, consumers select the `main` branch.

The Swift products contain no bundled scene assets. An integrating app chooses
its renderer and input adapters and retains control of permissions, sensor
lifecycle, accessibility behavior, and calibration.
