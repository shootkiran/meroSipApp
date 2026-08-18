import XCTest
@testable import MeroSipLib

@MainActor
final class CallHistoryTests: XCTestCase {
    var historyRepo: CallHistoryRepository!
    
    override func setUp() async throws {
        historyRepo = CallHistoryRepository()
    }
    
    func testAddAndRetrieveRecords() {
        let initialCount = historyRepo.callRecords.count
        
        historyRepo.addRecord(
            remoteUri: "9999",
            remoteDisplayName: "Test Call",
            direction: .outgoing,
            duration: 120,
            isMissed: false
        )
        
        XCTAssertEqual(historyRepo.callRecords.count, initialCount + 1)
        XCTAssertEqual(historyRepo.callRecords.first?.remoteUri, "9999")
        XCTAssertEqual(historyRepo.callRecords.first?.remoteDisplayName, "Test Call")
        XCTAssertEqual(historyRepo.callRecords.first?.formattedDuration, "02:00")
    }
    
    func testDeleteRecord() {
        historyRepo.addRecord(
            remoteUri: "8888",
            remoteDisplayName: "To Delete",
            direction: .incoming,
            duration: 10,
            isMissed: false
        )
        
        guard let record = historyRepo.callRecords.first(where: { $0.remoteUri == "8888" }) else {
            XCTFail("Record not found")
            return
        }
        
        historyRepo.deleteRecord(id: record.id)
        XCTAssertFalse(historyRepo.callRecords.contains(where: { $0.id == record.id }))
    }
}
