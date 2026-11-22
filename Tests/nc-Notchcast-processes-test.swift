// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastProcesses.swift
import Darwin

@main
enum NotchcastProcessesTests {
    static func main() {
        let pid = getpid()
        precondition(NotchcastProcesses.pids().contains(pid), "The reader lists its own PID")
        guard let usage = NotchcastProcesses.usage(pid) else {
            fatalError("The reader returns usage for its own PID")
        }
        precondition(usage.cpuNanoseconds > 0, "Own CPU time converts with the live timebase")
        precondition(usage.footprint > 0, "Own physical footprint is positive")
        precondition(NotchcastProcesses.usage(1) == nil, "An unprivileged reader cannot read launchd's usage")

        let unusedPID = pid_t.max
        precondition(kill(unusedPID, 0) == -1 && errno == ESRCH, "The unused PID has no process")
        precondition(NotchcastProcesses.usage(unusedPID) == nil, "The reader returns no usage for an unused PID")

        precondition(NotchcastProcesses.nanoseconds(ticks: 3_000, numerator: 125, denominator: 3) == 125_000,
                     "Mach ticks scale by the timebase ratio")
        precondition(NotchcastProcesses.nanoseconds(ticks: 1, numerator: 1, denominator: 0) == nil,
                     "A zero timebase denominator returns no sample")
        precondition(NotchcastProcesses.nanoseconds(ticks: .max, numerator: 125, denominator: 3) == nil,
                     "An overflowing conversion returns no sample")
        print("PASSED")
    }
}
