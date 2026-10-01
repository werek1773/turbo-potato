import Foundation
import Supabase

/// Maps the machine-readable error keys raised by the database to Polish.
enum UserFacingError {
    static func message(for error: any Error) -> String {
        if let postgrest = error as? PostgrestError {
            return known[postgrest.message] ?? postgrest.message
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "Brak połączenia z internetem."
        }
        return error.localizedDescription
    }

    private static let known: [String: String] = [
        "forbidden": "Nie masz uprawnień do tej operacji.",
        "not_authenticated": "Zaloguj się ponownie.",
        "last_manager": "Ścianka musi mieć przynajmniej jednego managera.",
        "stale_photo": "Ktoś właśnie zmienił zdjęcie tego sektora. Odśwież i spróbuj jeszcze raz.",
        "sector_has_no_photo": "Najpierw dodaj zdjęcie sektora.",
        "sector_archived": "Ten sektor jest zarchiwizowany.",
        "invalid_grade": "Ta wycena nie jest dostępna.",
        "photo_not_uploaded": "Zdjęcie nie zostało jeszcze przesłane.",
        "problem_removed": "Ten problem został już zdjęty.",
        "before_problem_set": "Tego dnia problemu jeszcze nie było.",
        "future_date": "Nie można zapisać przejścia w przyszłości.",
        "flash_not_first_attempt": "Flash jest możliwy tylko przy pierwszej próbie.",
        "health_consent_required": "Najpierw włącz zapisywanie samopoczucia w Profilu.",
        "cannot_restore": "Tego problemu nie da się przywrócić po przykrętce.",
    ]
}
