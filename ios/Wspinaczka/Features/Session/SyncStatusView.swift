import BoulderKit
import SwiftUI

/// One quiet line under the day header: are my taps on the server yet?
struct SyncStatusView: View {
    let log: SessionLog

    private var outbox: JournalOutbox { log.outbox }

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            Text(message)
                .lineLimit(2)
                .foregroundStyle(isProblem ? Palette.ink : Palette.muted)
            Spacer(minLength: 4)
            if let action {
                Button(action.title, action: action.run)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 4)
        .animation(.default, value: message)
        .accessibilityElement(children: .combine)
    }

    private enum Kind {
        case rejected(String)
        case failing(Int, String)
        case waiting(Int)
        case sending(Int)
        case offlineData
        case loadFailed(String)
        case saved
    }

    private var kind: Kind {
        if let rejection = outbox.rejection { return .rejected(rejection) }
        switch outbox.status {
        case let .failing(pending, message): return .failing(pending, message)
        case let .waitingForNetwork(pending): return .waiting(pending)
        case let .sending(pending): return .sending(pending)
        case .saved: break
        }
        if let error = log.loadError {
            return log.isLoadErrorConnectivity ? .offlineData : .loadFailed(error)
        }
        return .saved
    }

    private var isProblem: Bool {
        switch kind {
        case .rejected, .failing, .loadFailed: true
        default: false
        }
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .rejected, .failing, .loadFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.coral)
        case .waiting, .offlineData:
            Image(systemName: "wifi.slash").foregroundStyle(Palette.mustardText)
        case .sending:
            ProgressView().controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.moss)
        }
    }

    private var message: String {
        switch kind {
        case let .rejected(message):
            "Nie zapisano: \(message)"
        case let .failing(pending, message):
            "Błąd zapisu (\(pending)): \(message)"
        case let .waiting(pending):
            "Czeka na sieć (\(pending))"
        case let .sending(pending):
            "Zapisywanie… (\(pending))"
        case .offlineData:
            if let cachedAt = log.catalog.cachedAt {
                "Brak sieci — dane z \(cachedAt.formatted(.relative(presentation: .named)))"
            } else {
                "Brak połączenia z internetem."
            }
        case let .loadFailed(message):
            "Nie udało się odświeżyć: \(message)"
        case .saved:
            "Zapisano"
        }
    }

    private var action: (title: String, run: () -> Void)? {
        switch kind {
        case .rejected:
            ("OK", { outbox.dismissRejection() })
        case .failing, .waiting:
            ("Ponów", { outbox.flushNow() })
        case .offlineData, .loadFailed:
            ("Ponów", { Task { await log.load() } })
        case .sending, .saved:
            nil
        }
    }
}
