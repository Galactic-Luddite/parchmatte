import Cocoa

if CommandLine.arguments.count == 2,
   let domain = Bundle.main.bundleIdentifier,
   ["--audit-export-preferences", "--audit-import-preferences"].contains(CommandLine.arguments[1]) {
    do {
        if CommandLine.arguments[1] == "--audit-export-preferences" {
            FileHandle.standardOutput.write(try AuditPreferences.export(from: .standard, domain: domain))
        } else {
            try AuditPreferences.restore(FileHandle.standardInput.readDataToEndOfFile(), to: .standard, domain: domain)
        }
        exit(0)
    } catch {
        fputs("Parchmatte preference audit failed: \(error)\n", stderr)
        exit(2)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
