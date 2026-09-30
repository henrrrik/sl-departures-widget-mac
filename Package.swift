// swift-tools-version: 6.0
import PackageDescription

// SLKit holds every parsing, filtering and formatting rule the app and the
// widget share. It deliberately imports nothing but Foundation, so `swift test`
// exercises the whole model without Xcode, an app bundle, or a running UI —
// the same bet the Omarchy widget made by keeping Model.js free of QML types.
let package = Package(
    name: "SLKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SLKit", targets: ["SLKit"]),
        .executable(name: "sl-departures", targets: ["sl-departures"])
    ],
    targets: [
        .target(name: "SLKit", resources: [.process("Resources")]),
        // The terminal half: finding a stop id, and checking by hand what the
        // menu bar is claiming. The Omarchy repo's `bin/sl-sites` cannot run
        // here — it is GNU `stat -c` all the way down.
        .executableTarget(name: "sl-departures", dependencies: ["SLKit"]),
        .testTarget(
            name: "SLKitTests",
            dependencies: ["SLKit"],
            resources: [.copy("Fixtures")]
        ),
        // Compile the production coordinators directly for lifecycle tests,
        // without launching an app or requiring a signed widget bundle.
        .target(name: "AppSupport", dependencies: ["SLKit"], path: "App",
                exclude: ["main.swift", "AppDelegate.swift", "BoardView.swift", "SettingsView.swift",
                          "SiteSearch.swift", "StatusItemController.swift", "Assets.xcassets",
                          "Localizable.xcstrings", "InfoPlist.xcstrings", "Info.plist"],
                sources: ["DepartureHub.swift", "SettingsStore.swift"]),
        .testTarget(name: "AppSupportTests", dependencies: ["AppSupport", "SLKit"]),
        .target(name: "WidgetSupport", dependencies: ["SLKit"], path: "Widget",
                exclude: ["DeparturesWidget.swift", "Localizable.xcstrings", "InfoPlist.xcstrings",
                          "Info.plist", "SLWidget.entitlements"],
                sources: ["DeparturesProvider.swift", "DeparturesIntent.swift", "SiteEntity.swift"]),
        .testTarget(name: "WidgetSupportTests", dependencies: ["WidgetSupport", "SLKit"])
    ]
)
