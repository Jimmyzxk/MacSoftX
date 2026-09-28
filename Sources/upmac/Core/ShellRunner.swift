import Foundation

public enum ShellRunner {
    // MARK: - GUI 窄 PATH 修复：用户登录 shell PATH 探测（缓存）
    private static let userPathLock = NSLock()
    private static var _cachedUserPATH: String?

    /// 解析用户登录 shell 的 PATH（GUI 进程不继承 shell 配置，需主动探测）；结果缓存
    public static func resolvedUserPATH() -> String {
        userPathLock.lock()
        defer { userPathLock.unlock() }
        if let cached = _cachedUserPATH { return cached }
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        var result = fallback
        if let probe = syncRunForPATHProbe("/bin/zsh", ["-lc", "echo $PATH"], timeout: 5),
           probe.exitCode == 0
        {
            let trimmed = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result = trimmed }
        }
        for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !result.contains(extra) {
            result = extra + ":" + result
        }
        _cachedUserPATH = result
        return result
    }

    /// 仅用于 resolvedUserPATH 的同步探测 helper（Process + waitUntilExit + 管道读取，5s 超时）
    /// 这是唯一允许同步阻塞的地方，仅执行一次且极快
    private static func syncRunForPATHProbe(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> ShellResult? {
        guard FileManager.default.fileExists(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        // 超时等待：轮询 wait 避免永久阻塞
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                // 给 0.2s 优雅退出，否则 SIGKILL
                let killDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning && Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return ShellResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    // MARK: - 全局活跃进程注册表（退出清理）
    private static let activeLock = NSLock()
    private static var activePids: Set<Int32> = []

    private static func registerPid(_ pid: Int32) {
        guard pid > 0 else { return }
        activeLock.lock()
        activePids.insert(pid)
        activeLock.unlock()
    }

    private static func deregisterPid(_ pid: Int32) {
        guard pid > 0 else { return }
        activeLock.lock()
        activePids.remove(pid)
        activeLock.unlock()
    }

    /// 退出时终止所有活跃子进程（SIGTERM → 0.5s 后 SIGKILL 兜底）
    public static func terminateAllActive() {
        activeLock.lock()
        let pids = activePids
        activeLock.unlock()
        for pid in pids {
            // 发送 SIGTERM 到单进程
            kill(pid, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            activeLock.lock()
            let remaining = activePids
            activeLock.unlock()
            for pid in remaining {
                kill(pid, SIGKILL)
            }
        }
    }

    public struct ShellResult: Sendable, Codable, Equatable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        func tryResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }
    }

    private final class ProcessRunner: @unchecked Sendable {
        let process: Process
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
        private let lock = NSLock()
        private var _didTimeout = false

        var didTimeout: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _didTimeout
        }

        init(launchPath: String, arguments: [String], environment: [String: String]? = nil) {
            self.process = Process()
            self.process.executableURL = URL(fileURLWithPath: launchPath)
            self.process.arguments = arguments
            if let env = environment {
                self.process.environment = env
            }
            self.stdoutPipe = Pipe()
            self.stderrPipe = Pipe()
            self.process.standardOutput = stdoutPipe
            self.process.standardError = stderrPipe
        }

        func markTimedOutAndTerminate() {
            lock.lock()
            _didTimeout = true
            lock.unlock()

            if process.isRunning {
                let pid = process.processIdentifier
                // 加固2：尝试进程组清理 kill(-pid, SIGTERM)，失败回落单进程
                // 局限：未通过 setpgid/posix_spawn 将子进程设为独立进程组时，kill(-pid) 可能失败或影响父进程组；
                // 若返回 -1 则回落到 process.terminate() / kill(pid)。
                var groupKillSucceeded = false
                if pid > 0 {
                    // kill(-pid, SIGTERM) 在未独立设组时可能失败（ESRCH/EINVAL），需检测
                    if kill(-pid, SIGTERM) == 0 {
                        groupKillSucceeded = true
                    }
                }
                if !groupKillSucceeded {
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [process] in
                    if process.isRunning {
                        if groupKillSucceeded {
                            kill(-pid, SIGKILL)
                        } else {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }

        func terminate() {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public static func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        guard FileManager.default.fileExists(atPath: launchPath) else {
            throw ProviderError.managerMissing(launchPath)
        }

        // GUI 窄 PATH 修复：基环境注入 resolvedUserPATH，extra 优先
        var base = ProcessInfo.processInfo.environment
        base["PATH"] = resolvedUserPATH()
        if let extra = environment {
            base.merge(extra) { _, new in new }
        }
        let runner = ProcessRunner(launchPath: launchPath, arguments: arguments, environment: base)

        return try await withThrowingTaskGroup(of: ShellResult.self) { group in
            // 1. 进程执行任务（异步化：terminationHandler 驱动 resume，不阻塞协作线程）
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
                    let pipeGroup = DispatchGroup()
                    let stdoutBox = DataBox()
                    let stderrBox = DataBox()
                    let resumeBox = ResumeBox()

                    do {
                        runner.process.terminationHandler = { proc in
                            deregisterPid(proc.processIdentifier)
                            pipeGroup.wait()
                            guard resumeBox.tryResume() else { return }
                            if runner.didTimeout {
                                continuation.resume(throwing: ProviderError.timedOut)
                            } else {
                                let stdoutString = String(data: stdoutBox.value, encoding: .utf8) ?? ""
                                let stderrString = String(data: stderrBox.value, encoding: .utf8) ?? ""
                                continuation.resume(returning: ShellResult(
                                    exitCode: proc.terminationStatus,
                                    stdout: stdoutString,
                                    stderr: stderrString
                                ))
                            }
                        }

                        try runner.process.run()
                        registerPid(runner.process.processIdentifier)
                        try? runner.stdoutPipe.fileHandleForWriting.close()
                        try? runner.stderrPipe.fileHandleForWriting.close()

                        pipeGroup.enter()
                        DispatchQueue.global().async {
                            stdoutBox.value = runner.stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            pipeGroup.leave()
                        }

                        pipeGroup.enter()
                        DispatchQueue.global().async {
                            stderrBox.value = runner.stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            pipeGroup.leave()
                        }

                        // 不再调用 waitUntilExit()，由 terminationHandler 异步 resume
                    } catch {
                        runner.process.terminationHandler = nil
                        guard resumeBox.tryResume() else { return }
                        if runner.didTimeout {
                            continuation.resume(throwing: ProviderError.timedOut)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            // 2. 超时监控任务
            group.addTask {
                let delayNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNanoseconds)
                runner.markTimedOutAndTerminate()
                throw ProviderError.timedOut
            }

            // 3. 等待首个完成任务
            do {
                guard let first = try await group.next() else {
                    deregisterPid(runner.process.processIdentifier)
                    throw ProviderError.timedOut
                }
                guard !runner.didTimeout else {
                    deregisterPid(runner.process.processIdentifier)
                    throw ProviderError.timedOut
                }
                group.cancelAll()
                deregisterPid(runner.process.processIdentifier)
                return first
            } catch {
                runner.terminate()
                deregisterPid(runner.process.processIdentifier)
                group.cancelAll()
                throw error
            }
        }
    }
}
