import SwiftUI

/// Call History Recents list screen with All / Missed tabs.
public struct RecentsView: View {
    @ObservedObject var callManager: CallManager
    @ObservedObject var historyRepo = CallHistoryRepository.shared
    
    @State private var filterMode: FilterMode = .all
    @State private var searchQuery = ""
    
    public enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case missed = "Missed"
        public var id: String { rawValue }
    }
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    private var filteredRecords: [CallRecord] {
        let base = historyRepo.callRecords.filter { record in
            switch filterMode {
            case .all:
                return true
            case .missed:
                return record.isMissed
            }
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        
        return base.filter {
            $0.remoteDisplayName.lowercased().contains(query) ||
            $0.remoteUri.contains(query)
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Segmented Control
                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if filteredRecords.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: filterMode == .missed ? "phone.badge.checkmark" : "phone.arrow.up.right")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(filterMode == .missed ? "No Missed Calls" : "No Call History")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredRecords) { record in
                            RecentsRowView(record: record) {
                                callManager.startCall(to: record.remoteUri, displayName: record.remoteDisplayName)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    historyRepo.deleteRecord(id: record.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .searchable(text: $searchQuery, prompt: "Search recents")
            .navigationTitle("Recents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !historyRepo.callRecords.isEmpty {
                        Button("Clear") {
                            historyRepo.clearHistory()
                        }
                    }
                }
            }
        }
    }
}
