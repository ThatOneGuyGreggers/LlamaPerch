import Darwin
import Foundation

/// Thread-safe byte-bounded log retention shared by both pipe readers. Snapshots include partial lines.
public final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []
    private var bytes = 0
    private var partial: [String: Data] = [:]
    private var discarding: Set<String> = []
    public static let byteLimit = 1_048_576
    public static let recordLimit = 10_000
    private let lineLimit = 16_384

    private let inputLimit: Int?
    private var received = 0
    private var exceeded = false

    public init(inputLimit: Int? = nil) { self.inputLimit = inputLimit }

    public var overflowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceeded
    }

    public func append(_ data: Data, channel: String) {
        lock.lock()
        defer { lock.unlock() }
        if let inputLimit {
            guard received <= inputLimit - data.count else { exceeded = true; return }
            received += data.count
        }
        // Work is bounded by the reader's 4096-byte chunks, even for output without newlines.
        for byte in data {
            if byte == 10 { finishLine(channel); continue }
            if discarding.contains(channel) { continue }
            partial[channel, default: Data()].append(byte)
            if partial[channel, default: Data()].count >= lineLimit {
                add(
                    "[\(channel)] "
                        + String(decoding: partial.removeValue(forKey: channel) ?? Data(), as: UTF8.self)
                        + " [truncated]")
                discarding.insert(channel)
            }
        }
    }

    private func finishLine(_ channel: String) {
        if discarding.remove(channel) != nil { return }
        let data = partial.removeValue(forKey: channel) ?? Data()
        add("[\(channel)] " + String(decoding: data, as: UTF8.self))
    }

    private func add(_ record: String) {
        records.append(record)
        bytes += record.utf8.count + 1
        while bytes > Self.byteLimit || records.count > Self.recordLimit {
            bytes -= records.removeFirst().utf8.count + 1
        }
    }

    public func note(_ text: String) {
        append(Data((text + "\n").utf8), channel: "app")
    }

    public func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        let pending = partial.keys.sorted().map {
            "[\($0)] " + String(decoding: partial[$0] ?? Data(), as: UTF8.self)
        }
        let text = (records + pending).joined(separator: "\n")
        return String(decoding: text.utf8.suffix(Self.byteLimit - 3), as: UTF8.self)
    }
}

/// Drains a pipe off the main thread and signals EOF without queueing UI work per chunk.
final class PipeReader: @unchecked Sendable {
    let pipe = Pipe()
    private let queue: DispatchQueue
    private let finished = NSLock()
    private var ended = false
    private let buffer: LogBuffer

    init(buffer: LogBuffer, channel: String) {
        self.buffer = buffer
        queue = DispatchQueue(label: "LlamaPerch.pipe.\(channel).\(UUID())")
        queue.async { [self] in
            defer { finished.lock(); ended = true; finished.unlock() }
            defer {
                do { try pipe.fileHandleForReading.close() } catch {
                    buffer.note("Closing \(channel) failed: \(error.localizedDescription)")
                }
            }
            do {
                // POSIX read returns available bytes immediately; FileHandle may wait to fill a chunk.
                // EOF ends this loop when the owned child closes its writer.
                var chunk = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &chunk, chunk.count)
                    if count == 0 { break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw AppFailure("Pipe read failed: \(String(cString: strerror(errno)))")
                    }
                    buffer.append(Data(chunk.prefix(count)), channel: channel)
                }
            } catch { buffer.note("Reading \(channel) failed: \(error.localizedDescription)") }
        }
    }

    func closeWriter() {
        do { try pipe.fileHandleForWriting.close() } catch {
            buffer.note("Closing the parent pipe writer failed: \(error.localizedDescription)")
        }
    }

    var isFinished: Bool {
        finished.lock()
        defer { finished.unlock() }
        return ended
    }
}
