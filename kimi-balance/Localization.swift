import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    static let storageKey = "appLanguage"

    static var preferred: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else { return preferred }
        return language
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }

    fileprivate var bundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}

func localized(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(
        key,
        tableName: nil,
        bundle: AppLanguage.current.bundle,
        value: key,
        comment: ""
    )
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
