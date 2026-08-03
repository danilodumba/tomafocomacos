import XCTest
@testable import TomafocoDomain

/// Mapeamento entre o `Int?` cru do EventKit e os quatro níveis do Lembretes (item 4).
final class TaskPriorityTests: XCTestCase {

    func test_initFromRaw_classificaFaixas() {
        XCTAssertEqual(TaskPriority(rawPriority: nil), .none)
        XCTAssertEqual(TaskPriority(rawPriority: 0), .none)
        XCTAssertEqual(TaskPriority(rawPriority: 1), .high)
        XCTAssertEqual(TaskPriority(rawPriority: 4), .high)
        XCTAssertEqual(TaskPriority(rawPriority: 5), .medium)
        XCTAssertEqual(TaskPriority(rawPriority: 6), .low)
        XCTAssertEqual(TaskPriority(rawPriority: 9), .low)
    }

    func test_rawPriority_valoresCanonicos() {
        XCTAssertNil(TaskPriority.none.rawPriority)
        XCTAssertEqual(TaskPriority.high.rawPriority, 1)
        XCTAssertEqual(TaskPriority.medium.rawPriority, 5)
        XCTAssertEqual(TaskPriority.low.rawPriority, 9)
    }

    /// Ida e volta pelos valores canônicos é estável (o que a UI grava, relê igual).
    func test_roundtripCanonico() {
        for level in TaskPriority.allCases {
            XCTAssertEqual(TaskPriority(rawPriority: level.rawPriority), level)
        }
    }
}
