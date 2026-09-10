// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum BrightnessPolicy {
    static let hdrThreshold: Double = 1.05

    // Gamma values are encoded rather than linear light. 1.5 is the calibrated
    // full-boost endpoint used for 600-nit XDR panels by BrightIntosh.
    // Keep below both that endpoint and the currently available EDR headroom.
    static func factor(headroom: Double, amount: Double) -> Float {
        guard headroom.isFinite, amount.isFinite, headroom > hdrThreshold else { return 1 }
        let ceiling = min(1.5, pow(headroom, 1 / 2.2))
        return Float(1 + (ceiling - 1) * min(max(amount, 0), 1))
    }

    static func nextFactor(current: Float, target: Float) -> Float {
        // Never retain an elevated gamma when macOS withdraws HDR headroom.
        target < current ? target : min(target, current + 0.04)
    }

    static func shouldRestoreBrightness(current: Float?, original: Float?) -> Bool {
        guard let current, let original else { return false }
        // Preserve subsequent adjustments made with the brightness keys.
        return current >= 0.995 && original < 0.995
    }
}
