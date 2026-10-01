import BoulderKit
import SwiftUI

extension HoldColor {
    var polishName: String {
        switch self {
        case .red: "czerwony"
        case .orange: "pomarańczowy"
        case .yellow: "żółty"
        case .green: "zielony"
        case .blue: "niebieski"
        case .purple: "fioletowy"
        case .pink: "różowy"
        case .black: "czarny"
        case .white: "biały"
        case .grey: "szary"
        case .brown: "brązowy"
        case .multi: "mieszany"
        }
    }

    var swatch: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .black: .black
        case .white: .white
        case .grey: .gray
        case .brown: .brown
        case .multi: .mint
        }
    }
}

extension GymRole {
    var polishName: String {
        switch self {
        case .manager: "Manager"
        case .routesetter: "Routesetter"
        }
    }
}

extension Gym {
    var displayName: String {
        [name, city].compactMap { $0 }.joined(separator: " · ")
    }
}
