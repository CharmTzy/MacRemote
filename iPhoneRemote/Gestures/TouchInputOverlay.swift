import SwiftUI
import UIKit

/// A transparent view carrying every gesture recognizer the remote viewer
/// needs, all attached to the same view so UIKit's `require(toFail:)` and
/// simultaneous-recognition APIs can resolve conflicts between them (tap
/// vs. double-tap vs. long-press vs. drag vs. two-finger scroll) — this is
/// more reliable than composing SwiftUI's own gesture types for a set this
/// varied, and gives finer control than iOS 17's SwiftUI gesture API
/// exposes on its own.
protocol TouchInputOverlayDelegate: AnyObject {
    func touchInputOverlay(_ overlay: TouchInputOverlayView, didTapAt location: CGPoint, count: Int)
    func touchInputOverlay(_ overlay: TouchInputOverlayView, didLongPressAt location: CGPoint)
    func touchInputOverlay(_ overlay: TouchInputOverlayView, dragDidChangeTo location: CGPoint, state: UIGestureRecognizer.State)
    func touchInputOverlay(_ overlay: TouchInputOverlayView, didScrollBy delta: CGPoint)
}

final class TouchInputOverlayView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: TouchInputOverlayDelegate?

    private lazy var singleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gesture.numberOfTapsRequired = 1
        return gesture
    }()

    private lazy var doubleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        return gesture
    }()

    private lazy var longPress: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.minimumPressDuration = 0.45
        return gesture
    }()

    private lazy var dragPan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDragPan(_:)))
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        return gesture
    }()

    private lazy var scrollPan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        gesture.minimumNumberOfTouches = 2
        gesture.maximumNumberOfTouches = 2
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: longPress)
        dragPan.require(toFail: longPress)

        for gesture in [singleTap, doubleTap, longPress, dragPan, scrollPan] as [UIGestureRecognizer] {
            gesture.delegate = self
            addGestureRecognizer(gesture)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        delegate?.touchInputOverlay(self, didTapAt: gesture.location(in: self), count: 1)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        delegate?.touchInputOverlay(self, didTapAt: gesture.location(in: self), count: 2)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        delegate?.touchInputOverlay(self, didLongPressAt: gesture.location(in: self))
    }

    @objc private func handleDragPan(_ gesture: UIPanGestureRecognizer) {
        delegate?.touchInputOverlay(self, dragDidChangeTo: gesture.location(in: self), state: gesture.state)
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        delegate?.touchInputOverlay(self, didScrollBy: translation)
    }
}

struct TouchInputOverlay: UIViewRepresentable {
    let onTap: (CGPoint, Int) -> Void
    let onLongPress: (CGPoint) -> Void
    let onDragChange: (CGPoint, UIGestureRecognizer.State) -> Void
    let onScroll: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress, onDragChange: onDragChange, onScroll: onScroll)
    }

    func makeUIView(context: Context) -> TouchInputOverlayView {
        let view = TouchInputOverlayView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: TouchInputOverlayView, context: Context) {}

    final class Coordinator: NSObject, TouchInputOverlayDelegate {
        let onTap: (CGPoint, Int) -> Void
        let onLongPress: (CGPoint) -> Void
        let onDragChange: (CGPoint, UIGestureRecognizer.State) -> Void
        let onScroll: (CGPoint) -> Void

        init(
            onTap: @escaping (CGPoint, Int) -> Void,
            onLongPress: @escaping (CGPoint) -> Void,
            onDragChange: @escaping (CGPoint, UIGestureRecognizer.State) -> Void,
            onScroll: @escaping (CGPoint) -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onDragChange = onDragChange
            self.onScroll = onScroll
        }

        func touchInputOverlay(_ overlay: TouchInputOverlayView, didTapAt location: CGPoint, count: Int) {
            onTap(location, count)
        }

        func touchInputOverlay(_ overlay: TouchInputOverlayView, didLongPressAt location: CGPoint) {
            onLongPress(location)
        }

        func touchInputOverlay(_ overlay: TouchInputOverlayView, dragDidChangeTo location: CGPoint, state: UIGestureRecognizer.State) {
            onDragChange(location, state)
        }

        func touchInputOverlay(_ overlay: TouchInputOverlayView, didScrollBy delta: CGPoint) {
            onScroll(delta)
        }
    }
}
