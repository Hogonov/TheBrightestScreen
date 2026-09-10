// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Foundation

struct GammaTable {
    let red: [CGGammaValue]
    let green: [CGGammaValue]
    let blue: [CGGammaValue]

    static func read(display: CGDirectDisplayID) throws -> GammaTable {
        // Quartz's 256-entry transfer table is the path used for extended gamma
        // on Apple Silicon. The reported hardware LUT size can be larger, but
        // that path may silently clamp extended values back to SDR.
        let capacity = min(CGDisplayGammaTableCapacity(display), 256)
        guard capacity >= 2, capacity <= 65536 else {
            throw BrighterError.message("Экран не предоставляет гамма-таблицу")
        }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count)
        guard result == .success, count >= 2, count <= capacity else {
            throw BrighterError.message("Не удалось прочитать гамма-таблицу (\(result.rawValue))")
        }
        let table = GammaTable(red: Array(red.prefix(Int(count))),
                               green: Array(green.prefix(Int(count))),
                               blue: Array(blue.prefix(Int(count))))
        guard table.isValid else { throw BrighterError.message("Некорректная гамма-таблица экрана") }
        return table
    }

    var isValid: Bool {
        red.count >= 2 && red.count == green.count && red.count == blue.count &&
        [red, green, blue].allSatisfy { channel in
            channel.allSatisfy { $0.isFinite && $0 >= 0 } &&
            (channel.last ?? 0) > (channel.first ?? 0)
        }
    }

    func scaled(by factor: Float) -> GammaTable {
        GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor },
                   blue: blue.map { $0 * factor })
    }

    @discardableResult
    func apply(display: CGDirectDisplayID) -> CGError {
        guard isValid else { return .illegalArgument }
        return CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
    }

    func approximatelyEquals(_ other: GammaTable, tolerance: Float = 0.01) -> Bool {
        guard red.count == other.red.count, green.count == other.green.count,
              blue.count == other.blue.count else { return false }
        return zip(red + green + blue, other.red + other.green + other.blue)
            .allSatisfy { abs($0 - $1) <= tolerance }
    }
}

enum BrighterError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
