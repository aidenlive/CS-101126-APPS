// swift-tools-version: 6.0
import PackageDescription

/*
 CardsiteKit — the platform-neutral core of the Cardsite Apple app.

 Models, the API client, error mapping, address rules and the token store.
 No SwiftUI, so it builds and tests with `swift test` on macOS and (minus the
 Keychain store, which is guarded by `canImport(Security)`) on Linux.

 The test fixtures are the bodies captured from a live API by
 ../../ContractTests/native-contract.sh. Refresh them with
 ../../scripts/sync-fixtures.sh after re-running the harness.
 */
let package = Package(
    name: "CardsiteKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CardsiteKit", targets: ["CardsiteKit"]),
    ],
    targets: [
        .target(name: "CardsiteKit"),
        .testTarget(
            name: "CardsiteKitTests",
            dependencies: ["CardsiteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
