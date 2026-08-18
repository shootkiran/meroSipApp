import XCTest
@testable import MeroSipLib

@MainActor
final class CallManagerTests: XCTestCase {
    var callManager: CallManager!
    var sipEngine: RealSIPEngine!
    
    override func setUp() async throws {
        sipEngine = RealSIPEngine()
        callManager = CallManager(
            sipService: sipEngine,
            historyRepo: CallHistoryRepository.shared,
            audioRouteManager: AudioRouteManager.shared,
            callKitCoordinator: CallKitCoordinator.shared
        )
        
        let account = SIPAccount(
            username: "201",
            password: "795085b3462ee7a4dbdb7df4ae4dba0d",
            domain: "pbx.smartlink1.merosoftnepal.com",
            displayName: "Reception 1"
        )
        let user = AuthUser(id: "1", email: "reception_1", fullName: "Reception 1", organization: "SmartLink", sipExtension: "201")
        let response = ProvisioningResponse(user: user, sipAccount: account, authToken: "token")
        await callManager.configure(with: response)
    }
    
    func testAccountConfiguration() async {
        XCTAssertEqual(callManager.currentUser?.email, "reception_1")
        XCTAssertEqual(callManager.provisionedAccount?.username, "201")
        XCTAssertEqual(callManager.provisionedAccount?.domain, "pbx.smartlink1.merosoftnepal.com")
    }
    
    func testOutgoingCallAndHangup() async throws {
        callManager.startCall(to: "202", displayName: "Manager")
        
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertNotNil(callManager.activeCall)
        XCTAssertEqual(callManager.activeCall?.remoteUri, "202")
        XCTAssertEqual(callManager.activeCall?.direction, .outgoing)
        
        callManager.endCall()
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertNil(callManager.activeCall)
    }
    
    func testMuteAndHoldToggling() async throws {
        callManager.startCall(to: "203", displayName: "Sales")
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertFalse(callManager.activeCall?.isMuted ?? true)
        callManager.toggleMute()
        XCTAssertTrue(callManager.activeCall?.isMuted ?? false)
        
        XCTAssertFalse(callManager.activeCall?.isOnHold ?? true)
        callManager.toggleHold()
        XCTAssertTrue(callManager.activeCall?.isOnHold ?? false)
        
        callManager.endCall()
    }
    
    func testIncomingCallReception() async throws {
        let incomingSession = CallSession(
            callId: 888,
            remoteUri: "204",
            remoteDisplayName: "Executive",
            direction: .incoming,
            state: .ringing(isIncoming: true)
        )
        
        callManager.sipService(sipEngine, didReceiveIncomingCall: incomingSession)
        
        XCTAssertNotNil(callManager.activeCall)
        XCTAssertEqual(callManager.activeCall?.direction, .incoming)
        XCTAssertEqual(callManager.activeCall?.remoteDisplayName, "Executive")
        
        callManager.answerCall()
        try await Task.sleep(nanoseconds: 50_000_000)
        
        callManager.endCall()
    }
}
