// swift-tools-version:5.9
// The one build definition. Xcode opens this file directly (File > Open), builds only the files
// that changed, and runs the app with Cmd+R; build.sh calls `swift build -c release` on the same
// definition and puts the result in a bundle. Nothing about how the app compiles lives anywhere else.
//
// The sources are the .swift files at the repository root, as they always have been. Folders
// that hold other things (the helper, vendored frameworks, tools, help, designs) are excluded.
import PackageDescription

// Sparkle is the vendored framework in vendor/Sparkle. The first rpath finds it inside the bundle;
// the second lets the bare binary run from the build folder, for Xcode and for the self-test.
let root = Context.packageDirectory
let sparkle = "\(root)/vendor/Sparkle"

let package = Package(
    name: "MMFFDevColour3",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MMFFDevColour3",
            path: ".",
            exclude: [
                "Package.swift",
                "helper", "vendor", "tools", "help", "design", "assets", "icons", "installer", "release", "appstore",
                "Claude outputs", ".build", ".swiftpm", ".idea", ".claude",
                "AppIcon.icns", "Info.plist",
                "build.sh", "make_dmg.sh", "make_pkg.sh", "make_appstore.sh", "signing.sh", "store_notary_credentials.sh",
                "COLOUR-MANAGEMENT.md", "HANDOVER.md", "PALETTE-PAGE-DESIGNS.md", "README.md", "scratch.md",
                "Colour Management App Product Vision and Feature Deep Dive.md", "Research Software.md",
                "MMFFDev-Colour-3.dmg", "MMFFDev-Colour-3.pkg",
            ],
            swiftSettings: [
                .unsafeFlags(["-F", sparkle]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", sparkle, "-framework", "Sparkle",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", sparkle,
                ]),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
