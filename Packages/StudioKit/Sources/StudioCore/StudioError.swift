import Foundation

public enum StudioError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case corruptProject(String)
    case newerFormat(kind: String, found: Int, supported: Int)
    case engine(String)
    case io(String)
    case cancelled
    case notAvailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let s): "File non supportato: \(s)"
        case .corruptProject(let s): "Progetto danneggiato o illeggibile: \(s)"
        case .newerFormat(let k, let f, let s):
            "Il progetto \(k) usa il formato v\(f), ma questa versione dell'app legge fino alla v\(s). Aggiorna l'app."
        case .engine(let s): "Errore del motore: \(s)"
        case .io(let s): "Errore di lettura/scrittura: \(s)"
        case .cancelled: "Operazione annullata"
        case .notAvailable(let s): "Funzione non disponibile: \(s)"
        }
    }
}
