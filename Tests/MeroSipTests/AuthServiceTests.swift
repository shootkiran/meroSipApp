import XCTest
@testable import MeroSipLib

final class AuthServiceTests: XCTestCase {
    var authService: AuthService!
    
    override func setUp() {
        authService = AuthService()
    }
    
    override func tearDown() async throws {
        await authService.logout()
    }
    
    func testSuccessfulLoginAndAutoProvisioning() async throws {
        // Authenticate against production server with valid reception_1 credentials
        let response = try await authService.login(email: "reception_1", password: "reception_1")
        
        XCTAssertEqual(response.user.email, "reception_1")
        XCTAssertEqual(response.sipAccount.username, "201")
        XCTAssertTrue(response.sipAccount.domain.contains("merosoftnepal.com"))
        XCTAssertFalse(response.authToken.isEmpty)
    }
    
    func testInvalidCredentialsRejection() async {
        do {
            _ = try await authService.login(email: "non_existent_user_9999", password: "invalid_password_xyz")
            XCTFail("Should fail with invalid credentials")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    func testSessionRestoreAndLogout() async throws {
        let response = try await authService.login(email: "reception_1", password: "reception_1")
        XCTAssertNotNil(response)
        
        let restored = await authService.restoreSession()
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.user.email, "reception_1")
        
        await authService.logout()
        let cleared = await authService.restoreSession()
        XCTAssertNil(cleared)
    }
}
