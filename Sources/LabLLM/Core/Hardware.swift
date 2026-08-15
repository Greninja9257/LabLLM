import Foundation

/// Lightweight hardware probe for the profiler panel. Uses sysctl + ProcessInfo;
/// no private APIs. GPU core count isn't cheaply available without Metal
/// reflection, so we report chip, RAM, and CPU/perf-core counts.
struct HardwareInfo {
    let chip: String
    let physicalMemoryGB: Double
    let processorCount: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let isAppleSilicon: Bool

    static func current() -> HardwareInfo {
        let chip = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.model")
            ?? "Unknown"
        let mem = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let cores = ProcessInfo.processInfo.processorCount
        let perf = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let eff = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        #if arch(arm64)
        let arm = true
        #else
        let arm = false
        #endif
        return HardwareInfo(chip: chip,
                            physicalMemoryGB: mem,
                            processorCount: cores,
                            performanceCores: perf,
                            efficiencyCores: eff,
                            isAppleSilicon: arm)
    }

    /// Very rough model-size guidance from available RAM (weights + optimizer
    /// state + activations in fp32/bf16). Intentionally conservative.
    var recommendedMaxParameters: Int {
        let usableGB = max(physicalMemoryGB - 4.0, 2.0)   // leave headroom for macOS
        // ~16 bytes/param for AdamW state in fp32 training is a safe upper bound.
        return Int(usableGB * 1_073_741_824.0 / 16.0)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
