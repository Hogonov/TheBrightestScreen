// SPDX-License-Identifier: GPL-3.0-only
// The 1-point EDR trigger technique is based on BrightIntosh by Niklas Rousset.
import AppKit
import MetalKit

final class HDRTrigger: NSPanel {
    let metalView: HDRPixelView

    init(screen: NSScreen) throws {
        metalView = try HDRPixelView(edrValue: 1.6)
        super.init(contentRect: Self.pixelRect(screen), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Brighter HDR pixel"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = metalView
        orderFrontRegardless()
        metalView.draw()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func pixelRect(_ screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
    }

    func refresh(screen: NSScreen) {
        // The trigger must NEVER acquire the screen's size, even during Spaces,
        // mirroring, hot-plugging, display scaling or full-screen transitions.
        let rect = Self.pixelRect(screen)
        if frame != rect { setFrame(rect, display: false) }
        orderFrontRegardless()
        metalView.draw()
    }

    func stop() {
        metalView.isPaused = true
        orderOut(nil)
        close()
    }
}

final class HDRPixelView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private(set) var completedFrames = 0
    private(set) var lastFrameAt: Date?

    init(edrValue: Double) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw BrighterError.message("Metal недоступен на этом Mac")
        }
        self.queue = queue
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: device)
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        clearColor = MTLClearColorMake(edrValue, edrValue, edrValue, 1)
        preferredFramesPerSecond = 5
        if let layer = layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.backgroundColor = NSColor.clear.cgColor
            // No compositing filter and no full-screen white surface.
        }
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("Not used") }

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            guard buffer.status == .completed else { return }
            DispatchQueue.main.async {
                self?.completedFrames += 1
                self?.lastFrameAt = Date()
            }
        }
        command.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
