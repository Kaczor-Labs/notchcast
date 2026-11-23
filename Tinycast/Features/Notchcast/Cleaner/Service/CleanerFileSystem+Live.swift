// Adapted from Dragos Tugui's Peel, OpenFiles.swift @ 20230794 (GPL-3.0).
// The Trash route draws on RemoveMacAI, Storage.swift @ 12cef18 (MIT).
import Darwin
import Foundation

struct LiveCleanerFileSystem: CleanerFileSystem {
    func inspect(_ url: URL) throws -> CleanerFile {
        let path = url.path
        var info = stat()
        guard lstat(path, &info) == 0 else { throw Self.fileError(errno) }
        let kind = info.st_mode & S_IFMT
        let isLink = kind == S_IFLNK
        var parent = stat()
        let parentPath = url.deletingLastPathComponent().path
        guard lstat(parentPath, &parent) == 0 else { throw Self.fileError(errno) }

        return CleanerFile(
            identity: .init(
                device: info.st_dev, inode: info.st_ino, birthSeconds: Int64(info.st_birthtimespec.tv_sec),
                birthNanoseconds: info.st_birthtimespec.tv_nsec),
            facts: PathFacts(
                path: path, isSymbolicLink: isLink,
                isSystemRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_IMMUTABLE | SF_NOUNLINK | SF_APPEND) != 0,
                isUserImmutable: info.st_flags & UInt32(UF_IMMUTABLE | UF_APPEND) != 0,
                isDirectory: kind == S_IFDIR, isWritable: !isLink && access(path, W_OK) == 0,
                isOwnedByCurrentUser: info.st_uid == geteuid(), parentIsWritable: access(parentPath, W_OK) == 0,
                parentIsSticky: parent.st_mode & S_ISVTX != 0),
            size: info.st_blocks * 512, modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: info.st_mtimespec.tv_nsec, changedSeconds: Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: info.st_ctimespec.tv_nsec, isRegularFile: kind == S_IFREG)
    }

    func children(of folder: URL, limit: Int) throws -> [String] {
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.fileError(errno) }
        guard let directory = fdopendir(descriptor) else {
            close(descriptor)
            throw CleanerFileError.unreadable
        }
        defer { closedir(directory) }

        var names: [String] = []
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw Self.fileError(errno) }
                return names
            }
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(bytes: $0.prefix(Int(entry.pointee.d_namlen)), encoding: .utf8)
            }
            guard let name else { throw CleanerFileError.unreadable }
            guard name != ".", name != ".." else { continue }
            guard names.count < limit else { throw CleanerHoldBack.scanLimit }
            names.append(name)
        }
    }

    func linkDestination(of url: URL) throws -> String {
        do {
            return try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        } catch {
            throw CleanerFileError.unreadable
        }
    }

    func openFiles() throws -> CleanerOpenFiles {
        let capacity = proc_listallpids(nil, 0) + 64
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = proc_listallpids(&pids, capacity * Int32(MemoryLayout<pid_t>.stride))
        guard count > 0, count < capacity else { throw CleanerFileError.unreadable }

        var files = CleanerOpenFiles()
        for pid in pids.prefix(Int(count)) where pid > 0 && pid != getpid() {
            try Task.checkCancellation()
            files.running.formUnion(Self.programs(runBy: pid).compactMap(Self.identity(at:)))
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            let stride = MemoryLayout<proc_fdinfo>.stride
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
            let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
            guard filled > 0 else { continue }
            for descriptor in descriptors.prefix(Int(filled) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
                try Task.checkCancellation()
                var info = vnode_fdinfo()
                let expected = Int32(MemoryLayout<vnode_fdinfo>.size)
                guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEINFO, &info, expected) == expected,
                    info.pfi.fi_openflags & UInt32(O_EVTONLY) == 0,
                    info.pvi.vi_stat.vst_mode & S_IFMT == S_IFREG
                else { continue }
                let stat = info.pvi.vi_stat
                files.held.insert(.init(
                    device: Int32(bitPattern: stat.vst_dev), inode: stat.vst_ino,
                    birthSeconds: stat.vst_birthtime, birthNanoseconds: Int(stat.vst_birthtimensec)))
            }
        }
        return files
    }

    func trash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    // A process runs from its program and, for a script runner, from each script named as an argument.
    private static func programs(runBy pid: pid_t) -> [String] {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return [] }
        let program = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let name = URL(filePath: program).lastPathComponent
        guard ["node", "deno", "bun", "ruby", "perl"].contains(name) || name.hasPrefix("python") else { return [program] }
        return [program] + (arguments(of: pid) ?? []).dropFirst().filter { $0.hasPrefix("/") }
    }

    // KERN_PROCARGS2 holds the argument count, the program path and its padding, then each argument.
    private static func arguments(of pid: pid_t) -> [String]? {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var name = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&name, u_int(name.count), &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        size = buffer.count
        name = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&name, u_int(name.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size
        else { return nil }
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < size {
            let end = buffer[index..<size].firstIndex(of: 0) ?? size
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }

    private static func identity(at path: String) -> CleanerFile.Identity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return .init(
            device: info.st_dev, inode: info.st_ino, birthSeconds: Int64(info.st_birthtimespec.tv_sec),
            birthNanoseconds: info.st_birthtimespec.tv_nsec)
    }

    private static func fileError(_ code: Int32) -> CleanerFileError {
        code == ENOENT ? .missing : .unreadable
    }
}
