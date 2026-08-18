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
        let response = try await authService.login(email: "john@company.com", password: "securepassword")
        
        XCTAssertEqual(response.user.email, "john@company.com")
        XCTAssertEqual(response.user.fullName, "John")
        XCTAssertTrue(response.sipAccount.domain.contains("company.com"))
        XCTAssertEqual(response.sipAccount.transport, .tls)
        XCTAssertTrue(response.sipAccount.srtpEnabled)
        XCTAssertFalse(response.authToken.isEmpty)
    }
    
    func testInvalidCredentialsRejection() async {
        do {
            _ = try await authService.login(email: "", password: "")
            XCTFail("Should fail with invalid credentials")
        } catch {
            XCTAssertTrue(true)
        }
    }
    
    func testSessionRestoreAndLogout() async throws {
        let response = try await authService.login(email: "test@merosip.com", password: "password")
        XCTAssertNotNil(response)
        
        let restored = await authService.restoreSession()
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.user.email, "test@merosip.com")
        
        await authService.logout()
        let cleared = await authService.restoreSession()
        XCTAssertNil(cleared)
    }
}
