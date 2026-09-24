import Foundation
import Darwin

/// Which editor window holds a session's terminal.
///
/// A Claude session can move (`cd`, a worktree) without its terminal moving,
/// so opening the session's own directory is wrong: VS Code opens a second
/// window with no terminal in it. Two better clues exist. The terminal's
/// shell, the session's parent process, still sits where the window was
/// opened. And VS Code writes the folder each of its windows has open to its
/// state file. Match one against the other.
public enum TerminalWindow {
    /// The parent process id, or nil when the process is gone.
    public static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// The process's current directory, or nil.
    public static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// The folders the editor's windows have open, from its state file
    /// (`windowsState.openedWindows[].folder` and `lastActiveWindow.folder`,
    /// as `file://` URLs). Workspace-file windows carry no folder and are
    /// skipped. Missing or unreadable file: none.
    public static func openFolders(inStorageFile url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["windowsState"] as? [String: Any]
        else { return [] }
        var windows = state["openedWindows"] as? [[String: Any]] ?? []
        if let last = state["lastActiveWindow"] as? [String: Any] { windows.append(last) }
        var folders: [String] = []
        for window in windows {
            guard let raw = window["folder"] as? String,
                  let fileURL = URL(string: raw), fileURL.isFileURL
            else { continue }
            let path = ProjectRoot.normalize(fileURL.path)
            if !folders.contains(path) { folders.append(path) }
        }
        return folders
    }

    /// The state files of the VS Code family that exist on this Mac.
    public static func storageFiles(applicationSupport: URL? = nil) -> [URL] {
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return [] }
        return ["Code", "Code - Insiders", "Cursor", "VSCodium"]
            .map { base.appendingPathComponent("\($0)/User/globalStorage/storage.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The first open folder that contains a candidate: each candidate is
    /// tried in turn, walking up from it, so the nearest window wins and the
    /// first candidate is trusted most.
    public static func windowFolder(candidates: [String], open: [String]) -> String? {
        let openSet = Set(open.map(ProjectRoot.normalize))
        for candidate in candidates where !candidate.isEmpty {
            var dir = ProjectRoot.normalize(candidate)
            while true {
                if openSet.contains(dir) { return dir }
                if dir == "/" { break }
                dir = (dir as NSString).deletingLastPathComponent
                if dir.isEmpty { dir = "/" }
            }
        }
        return nil
    }

    /// The folder to hand VS Code so the window holding this session's
    /// terminal comes forward: an open window's folder above the terminal
    /// shell's directory (or the session's), else the repository above the
    /// shell's directory, else the session's own directory.
    public static func folder(forSessionAt cwd: String, pid: pid_t) -> String {
        let shell = pid > 0 ? parentProcess(of: pid).flatMap(currentDirectory(of:)) : nil
        let candidates = [shell, cwd].compactMap { $0 }.filter { !$0.isEmpty }
        let open = storageFiles().flatMap(openFolders(inStorageFile:))
        if let match = windowFolder(candidates: candidates, open: open) { return match }
        if let first = candidates.first { return ProjectRoot.resolve(first) }
        return cwd
    }
}
