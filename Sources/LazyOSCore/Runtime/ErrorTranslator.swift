import Foundation

public enum ErrorTranslator {
    /// Maps raw docker / compose stderr into a friendly message.
    public static func friendly(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("cannot connect to the docker daemon") || s.contains("is the docker daemon running") {
            return "OrbStack isn't running. Open OrbStack and try again."
        }
        if s.contains("pull access denied") || s.contains("repository does not exist") {
            return "Couldn't download the app image. Check your internet, then try again."
        }
        if s.contains("port is already allocated") || s.contains("address already in use") || s.contains("bind: address already in use") {
            return "That port is in use by another app. LazyOS will pick a new one and retry."
        }
        if s.contains("no space left on device") {
            return "Your disk is full. Free up some space, then try again."
        }
        if s.contains("unauthorized") {
            return "Image registry rejected the download. Try again in a minute."
        }
        if s.contains("network") && s.contains("not found") {
            return "Internal network missing. LazyOS will recreate it on the next start."
        }
        // Trim to a single short line if no specific match.
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        return firstLine.isEmpty ? "Something went wrong starting this app." : firstLine
    }
}
