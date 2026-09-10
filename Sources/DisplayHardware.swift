// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var supportsBoost: Bool {
        guard displayID != 0, CGDisplayIsInMirrorSet(displayID) == 0 else { return false }
        // Restrict to Apple XDR-capable displays; HDR compatibility alone on an
        // arbitrary external monitor does not imply that this technique works.
        return maximumPotentialExtendedDynamicRangeColorComponentValue > 1 &&
            (CGDisplayIsBuiltin(displayID) != 0 || localizedName.localizedCaseInsensitiveContains("XDR"))
    }
}

final class NativeBrightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private let handle: UnsafeMutableRawPointer?
    private let getValue: Get?
    private let setValue: Set?

    init() {
        // Optional private Apple API, isolated behind runtime symbol checks.
        // XDR itself uses public CoreGraphics/Metal APIs and works without it.
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getValue = unsafeBitCast(get, to: Get.self)
            setValue = unsafeBitCast(set, to: Set.self)
        } else { getValue = nil; setValue = nil }
    }

    deinit { if let handle { dlclose(handle) } }

    func read(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getValue, getValue(display, &value) == 0,
              value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    @discardableResult
    func write(_ display: CGDirectDisplayID, value: Float) -> Bool {
        guard let setValue else { return false }
        return setValue(display, min(max(value, 0), 1)) == 0
    }
}
