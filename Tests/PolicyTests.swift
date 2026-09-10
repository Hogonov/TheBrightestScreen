import Foundation

@main enum PolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        for edr in [-10.0, 0, 1, 1.05, .nan, .infinity] {
            check(BrightnessPolicy.factor(headroom: edr, amount: 1) == 1, "SDR or invalid EDR must never boost")
        }
        check(BrightnessPolicy.factor(headroom: 2.66, amount: 1) == 1.5, "M3 XDR maximum")
        check(BrightnessPolicy.factor(headroom: 2.66, amount: 0) == 1, "Zero boost")
        check(BrightnessPolicy.factor(headroom: 2.66, amount: .nan) == 1, "Invalid input")
        for edr in stride(from: 1.06, through: 16.0, by: 0.1) {
            let factor = BrightnessPolicy.factor(headroom: edr, amount: 1)
            check(factor >= 1 && factor <= 1.5, "Bounded gamma")
            check(pow(Double(factor), 2.2) <= edr + 0.00001, "Must fit available HDR headroom")
        }
        check(BrightnessPolicy.nextFactor(current: 1.5, target: 1) == 1, "HDR loss must reset immediately")
        check(BrightnessPolicy.nextFactor(current: 1, target: 1.5) <= 1.041, "Smooth upward transition")
        check(BrightnessPolicy.shouldRestoreBrightness(current: 1, original: 0.6), "Restore app maximum")
        check(!BrightnessPolicy.shouldRestoreBrightness(current: 0.7, original: 0.6), "Keep subsequent user adjustment")
        check(!BrightnessPolicy.shouldRestoreBrightness(current: nil, original: 0.6), "Do not guess native brightness")
        let original = GammaTable(red: [0, 0.2, 0.7, 1], green: [0, 0.1, 0.5, 0.9], blue: [0, 0.3, 0.6, 0.8])
        check(original.isValid, "Valid non-neutral calibration")
        let boosted = original.scaled(by: 1.5)
        check(boosted.red.last == 1.5 && boosted.red.first == 0, "Retain black and lift white")
        check(abs(boosted.green.last! / boosted.red.last! - 0.9) < 0.00001, "Preserve channel ratios")
        check(original.red.last == 1, "Original calibration stays immutable")
        check(original.scaled(by: 1).approximatelyEquals(original), "Restore exact captured samples")
        check(!original.approximatelyEquals(boosted), "Detect another gamma curve")
        check(!GammaTable(red: [], green: [], blue: []).isValid, "Reject empty capture")
        check(!GammaTable(red: [0, 1], green: [0], blue: [0, 1]).isValid, "Reject mismatched capture")
        check(!GammaTable(red: [0, .nan], green: [0, 1], blue: [0, 1]).isValid, "Reject invalid samples")
        print("PASS: \(checks) policy and gamma checks")
    }
}
