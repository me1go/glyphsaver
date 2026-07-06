/// SplitMix64 — deterministic, seedable RNG so effect tests are reproducible
/// and each display can animate differently from the same build.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    public mutating func pick<T>(_ array: [T]) -> T {
        precondition(!array.isEmpty, "pick from empty array")
        return array[Int.random(in: 0..<array.count, using: &self)]
    }

    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        array.shuffled(using: &self)
    }
}

/// Stateless hash for procedural noise (stable per (seed, coordinates) — no storage needed).
public enum NoiseHash {
    public static func hash(_ a: UInt64, _ b: UInt64, _ c: UInt64 = 0) -> UInt64 {
        var z = a &* 0x9E37_79B9_7F4A_7C15 ^ b &* 0xBF58_476D_1CE4_E5B9 ^ c &* 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform [0, 1) from a hash.
    public static func unit(_ a: UInt64, _ b: UInt64, _ c: UInt64 = 0) -> Double {
        Double(hash(a, b, c) >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
