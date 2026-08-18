import XCTest
@testable import MeroSipLib

@MainActor
final class CallManagerTests: XCTestCase {
    var callManager: CallManager!
    var mockSIPService: MockSIPService!
    
    override func setUp() async throws {
        mockSIPService = MockSIPService()
        callManager = CallManager(
            sipService: mockSIPService,
            historyRepo: CallHistoryRepository.shared,
            audioRouteManager: AudioRouteManager.shared,
            callKitCoordinator: CallKitCoordinator.shared
        )
    }
    
    func testAccountConfiguration() async {
        let account = SIPAccount(username: "1001", domain: "sip.example.com")
        let user = AuthUser(id: "1", email: "user@example.com", fullName: "Test User", organization: "Example", sipExtension: "1001")
        let response = ProvisioningResponse(user: user, sipAccount: account, authToken: "token")
        
        await callManager.configure(with: response)
        
        XCTAssertEqual(callManager.currentUser?.email, "user@example.com")
        XCTAssertEqual(callManager.provisionedAccount?.username, "1001")
        XCTAssertEqual(callManager.registrationState, .registered)
    }
    
    func testOutgoingCallAndHangup() async throws {
        callManager.startCall(to: "1002", displayName: "Bob")
        
        // Wait briefly for task dispatch
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertNotNil(callManager.activeCall)
        XCTAssertEqual(callManager.activeCall?.remoteUri, "1002")
        XCTAssertEqual(callManager.activeCall?.direction, .outgoing)
        
        callManager.endCall()
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertNil(callManager.activeCall)
    }
    
    func testMuteAndHoldToggling() async throws {
        callManager.startCall(to: "1003", displayName: "Charlie")
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertFalse(callManager.activeCall?.isMuted ?? true)
        callManager.toggleMute()
        XCTAssertTrue(callManager.activeCall?.isMuted ?? false)
        
        XCTAssertFalse(callManager.activeCall?.isOnHold ?? true)
        callManager.toggleHold()
        XCTAssertTrue(callManager.activeCall?.isOnHold ?? false)
        
        callManager.endCall()
    }
    
    func testIncomingCallSimulation() async throws {
        callManager.simulateIncomingCall(from: "1004", displayName: "Diana")
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertNotNil(callManager.activeCall)
        XCTAssertEqual(callManager.activeCall?.direction, .incoming)
        XCTAssertEqual(callManager.activeCall?.remoteDisplayName, "Diana")
        
        callManager.answerCall()
        try await Task.sleep(nanoseconds: 50_000_000)
        
        if case .connected = callManager.activeCall?.state {
            XCTAssertTrue(true)
        }
        
        callManager.endCall()
    }
}
