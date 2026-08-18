import SwiftUI

/// Single row item in the call recents list.
public struct RecentsRowView: View {
    public let record: CallRecord
    public let onCall: () -> Void
    
    public init(record: CallRecord, onCall: @escaping () -> Void) {
        self.record = record
        self.onCall = onCall
    }
    
    private var directionIcon: String {
        if record.isMissed {
            return "phone.arrow.down.left.fill"
        }
        return record.direction == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right"
    }
    
    private var directionColor: Color {
        if record.isMissed {
            return .red
        }
        return record.direction == .incoming ? .blue : .secondary
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionIcon)
                .foregroundColor(directionColor)
                .font(.body)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(record.remoteDisplayName)
                    .font(.system(size: 15, weight: record.isMissed ? .semibold : .medium))
                    .foregroundColor(record.isMissed ? .red : .primary)
                
                HStack(spacing: 6) {
                    Text(record.remoteUri)
                    if record.duration > 0 {
                        Text("• \(record.formattedDuration)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formattedDate(record.date))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(action: onCall) {
                Image(systemName: "phone.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
