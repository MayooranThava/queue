import UIKit
import XCTest
@testable import Queue

final class QueueColorResolutionTests: XCTestCase {
    func testEveryColorRoleResolvesInLightAndDark() {
        for role in QueueColorRole.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: style),
                        UITraitCollection(accessibilityContrast: contrast)
                    ])
                    let name = "\(role.rawValue) style=\(style.rawValue) contrast=\(contrast.rawValue)"
                    let bundle = Bundle(identifier: "com.queueapp.Queueup") ?? .main
                    let color = UIColor(named: role.rawValue, in: bundle, compatibleWith: traits)
                    XCTAssertNotNil(color, name)
                    guard let resolved = color?.resolvedColor(with: traits) else {
                        XCTFail(name)
                        continue
                    }
                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    var alpha: CGFloat = 0
                    XCTAssertTrue(
                        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
                        name
                    )
                    XCTAssertEqual(alpha, 1, accuracy: 0.001, name)
                    XCTAssertGreaterThan(red + green + blue, 0.02, name)
                }
            }
        }
    }
}
