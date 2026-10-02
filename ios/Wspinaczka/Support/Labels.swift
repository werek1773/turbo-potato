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

extension StyleTag {
    var polishName: String {
        switch self {
        case .slab: "płyta"
        case .vertical: "pion"
        case .overhang: "przewieszenie"
        case .roof: "dach"
        case .crimps: "krawądki"
        case .slopers: "oblaki"
        case .pinches: "szczypy"
        case .pockets: "dziurki"
        case .jugs: "klamy"
        case .volumes: "struktury"
        case .dynamic: "dynamiczny"
        case .static: "statyczny"
        case .coordination: "koordynacja"
        case .compression: "kompresja"
        case .balance: "balans"
        }
    }
}

extension AscentResult {
    var polishName: String {
        switch self {
        case .flash: "Flash"
        case .top: "Top"
        case .project: "Projekt"
        }
    }

    var pictogram: Pictogram.Kind {
        switch self {
        case .flash: .flash
        case .top: .top
        case .project: .project
        }
    }

    var symbol: String {
        switch self {
        case .flash: "bolt.fill"
        case .top: "flag.fill"
        case .project: "circle.righthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .flash: Palette.ocean
        case .top: Palette.grass
        case .project: Palette.berry
        }
    }
}

extension AttemptsBucket {
    var polishName: String {
        switch self {
        case .one: "1"
        case .twoToThree: "2–3"
        case .fourToTen: "4–10"
        case .moreThanTen: "10+"
        }
    }
}

extension PerceivedGrade {
    var polishName: String {
        switch self {
        case .soft: "Miękka"
        case .ok: "W sam raz"
        case .hard: "Twarda"
        }
    }
}

extension Limiter {
    var polishName: String {
        switch self {
        case .fingerStrength: "siła palców"
        case .power: "siła / moc"
        case .endurance: "wytrzymałość"
        case .core: "core"
        case .flexibility: "rozciągnięcie"
        case .footwork: "praca nóg"
        case .balance: "balans"
        case .coordination: "koordynacja"
        case .beta: "czytanie drogi"
        case .fear: "strach"
        case .commitment: "zaangażowanie"
        case .conditions: "skóra / tarcie"
        }
    }
}

extension SkinState {
    var polishName: String {
        switch self {
        case .fresh: "Świeża"
        case .ok: "OK"
        case .thin: "Cienka"
        case .split: "Pęknięta"
        }
    }
}

extension BodyArea {
    var polishName: String {
        switch self {
        case .fingers: "palce"
        case .wrists: "nadgarstki"
        case .elbows: "łokcie"
        case .shoulders: "barki"
        case .back: "plecy"
        case .knees: "kolana"
        case .ankles: "kostki"
        case .other: "inne"
        }
    }
}
