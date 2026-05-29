import Foundation

/// Tails an append-only JSONL file using a DispatchSource vnode watcher plus a
/// low-frequency safety poll. Handles: file missing at launch, growth,
/// truncation, and rotation/recreation (detected via inode change). All IO runs
/// on a private serial queue; decoded events are delivered on the main queue.
final class SpoolTailer {
    private let path: String
    private let dirPath: String
    private let onEvents: ([SpoolEvent]) -> Void

    private let queue = DispatchQueue(label: "agentnotifier.spool.tailer")
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?

    private var fd: Int32 = -1
    private var offset: UInt64 = 0
    private var openedInode: UInt64 = 0
    private var lineBuffer = Data()

    init(path: String, onEvents: @escaping ([SpoolEvent]) -> Void) {
        self.path = path
        self.dirPath = (path as NSString).deletingLastPathComponent
        self.onEvents = onEvents
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureFileExists()
            self.reopen(readFromStart: false)   // skip existing backlog on first launch
            self.startPollTimer()
        }
    }

    // MARK: - File setup

    private func ensureFileExists() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
    }

    private func reopen(readFromStart: Bool) {
        source?.cancel()   // closes the previous fd in its cancel handler
        source = nil

        let newFd = open(path, O_RDONLY)
        guard newFd >= 0 else { fd = -1; return }
        fd = newFd

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let ino = attrs[.systemFileNumber] as? Int {
            openedInode = UInt64(ino)
        }

        lineBuffer.removeAll(keepingCapacity: true)
        if readFromStart {
            offset = 0
            lseek(fd, 0, SEEK_SET)
        } else {
            offset = UInt64(lseek(fd, 0, SEEK_END))
        }

        startWatching()
        if readFromStart { readNewData() }
    }

    private func startWatching() {
        let watchFd = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self = self, let src = src else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.reopen(readFromStart: true)
            } else {
                self.readNewData()
            }
        }
        src.setCancelHandler {
            close(watchFd)
        }
        source = src
        src.resume()
    }

    private func startPollTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.pump() }
        t.resume()
        pollTimer = t
    }

    // MARK: - Reading

    /// Safety net: re-check the path for missing/rotated file, otherwise read.
    private func pump() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            ensureFileExists()
            reopen(readFromStart: true)
            return
        }
        let pathInode = (attrs[.systemFileNumber] as? Int).map { UInt64($0) } ?? 0
        if fd < 0 {
            reopen(readFromStart: true)
            return
        }
        if pathInode != 0, pathInode != openedInode {
            reopen(readFromStart: true)
            return
        }
        readNewData()
    }

    private func readNewData() {
        guard fd >= 0 else { return }
        let end = UInt64(lseek(fd, 0, SEEK_END))
        if end < offset {            // truncated
            offset = 0
            lineBuffer.removeAll(keepingCapacity: true)
        }
        if end <= offset {
            lseek(fd, off_t(offset), SEEK_SET)
            return
        }
        lseek(fd, off_t(offset), SEEK_SET)
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                offset += UInt64(n)
                lineBuffer.append(contentsOf: buf[0..<n])
            } else {
                break
            }
        }
        processBuffer()
    }

    private func processBuffer() {
        var events: [SpoolEvent] = []
        let newline = Data([0x0A])
        while let r = lineBuffer.range(of: newline) {
            let lineData = lineBuffer.subdata(in: 0..<r.lowerBound)
            lineBuffer.removeSubrange(0..<r.upperBound)
            if lineData.isEmpty { continue }
            if let ev = try? JSONDecoder().decode(SpoolEvent.self, from: lineData) {
                events.append(ev)
            }
        }
        guard !events.isEmpty else { return }
        let captured = events
        DispatchQueue.main.async { [weak self] in
            self?.onEvents(captured)
        }
    }
}
