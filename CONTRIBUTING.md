# How to contribute

Thanks for your interest! Fork Crosswire, make a new branch for your changes, and get coding.

# Build environment

Crosswire is built with Xcode 26 on macOS and targets macOS 14.6 or later. All dependencies come through the Swift Package Manager, so opening `Crosswire.xcodeproj` and building is all it takes.

One caveat: the app icon and appearance rely on the macOS 26 SDK. Older Xcode versions will still build and run the app, but they silently drop the icon and fall back to the legacy look. Don't be alarmed if a local build looks plain, and don't try to "fix" it in a PR.

# How the library is modelled

One library item is one app, and each one gets its own isolated Windows environment on disk. The type is still called `Bottle` in the source, and that name stays: renaming it would churn the persisted metadata keys for no user-visible gain.

None of that vocabulary reaches the interface. No user-facing string names Wine, the engine, the wrappers, DXVK, Winetricks, bottles, prefixes or environments. Library items are "apps". Where the software that runs Windows apps has to be mentioned at all, in first-run setup, updates or uninstall, the term is "Windows support" and nothing else.

# Code style

Every Crosswire commit is automatically linted using SwiftLint. You can run these checks locally simply by building in Xcode; violations will appear as errors or warnings. For your pull request to be merged, you must meet all the requirements outlined by SwiftLint and have no violations.

Generally, it is not advised to disable a SwiftLint rule, but there are certain situations where it is necessary. Please use your discretion when disabling rules temporarily.

SwiftLint does not fully check indentation, but we ask that you indent with 4-width spaces. This can be automatically configured in Xcode's settings.

All added strings must be properly localised and added to the EN strings file. Do not add keys for other languages or translate within your PR.

# Making your PR

Please provide a detailed description of your changes in your PR. If your commits contain UI changes, we ask that you provide screenshots.

# Review

Once your pull request passes the SwiftLint and test checks it is ready for review. You may be asked to change things. Crosswire has one maintainer, so review can take a while, and an approving review is not a commitment to merge: a change that is sound on its own can still be turned down if it does not fit where the project is going. Open an issue first if you are planning something large, so that conversation happens before you write the code.
