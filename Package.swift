// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "SwiftDraw",
	  platforms: [
        .iOS(.v12), .macOS(.v10_14)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
		.library(
            name: "SwiftDraw",
            targets: ["SwiftDraw"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftDraw",
            dependencies: [],
			path: "SwiftDraw"
		)
    ]
)
