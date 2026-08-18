import Foundation

/// Telephony transfer mechanisms.
public enum TransferType: Sendable, Equatable {
    /// Blind transfer: Directs the remote party to call the target directly.
    case blind(targetUri: String)
    
    /// Attended transfer: Puts first call on hold, connects to second call, then bridges them.
    case attended(targetCallId: Int32)
}
