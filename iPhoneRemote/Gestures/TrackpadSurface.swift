import SwiftUI
import UIKit

/// Gesture bridge for trackpad mode. Deliberately separate from
/// `TouchInputOverlay` — trackpad's gesture set is smaller (no long-press;
/// two-finger tap is right-click instead) and means something different
/// (relative movement, not a position on the video), so keeping them apart
/// avoids one view's gestures being subtly wrong for the other's purpose.
protocol TrackpadSurfaceDelegate: AnyObject {
    func trackpadSurface(_ surface: TrackpadSurfaceView, didTapWithCount count: Int)
    func trackpadSurfaceDidRightTap(_ surface: TrackpadSurfaceView)
    func trackpadSurface(_ surface: TrackpadSurfaceView, panChangedBy translation: CGPoint, state: UIGestureRecognizer.State)
    func trackpadSurface(_ surface: TrackpadSurfaceView, didScrollBy delta: CGPoint)
}

final class TrackpadSurfaceView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: TrackpadSurfaceDelegate?

    private lazy var singleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        gesture.numberOfTapsRequired = 1
        return gesture
    }()

    private lazy var doubleTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        gesture.numberOfTapsRequired = 2
        return gesture
    }()

    private lazy var twoFingerTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        gesture.numberOfTouchesRequired = 2
        return gesture
    }()

    private lazy var pan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        return gesture
    }()

    private lazy var scrollPan: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan))
        gesture.minimumNumberOfTouches = 2
        gesture.maximumNumberOfTouches = 2
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        singleTap.require(toFail: doubleTap)
        for gesture in [singleTap, doubleTap, twoFingerTap, pan, scrollPan] as [UIGestureRecognizer] {
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
        delegate?.trackpadSurface(self, didTapWithCount: 1)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        delegate?.trackpadSurface(self, didTapWithCount: 2)
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        delegate?.trackpadSurfaceDidRightTap(self)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        delegate?.trackpadSurface(self, panChangedBy: translation, state: gesture.state)
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        delegate?.trackpadSurface(self, didScrollBy: translation)
    }
}

struct TrackpadSurface: UIViewRepresentable {
    let onTap: (Int) -> Void
    let onRightTap: () -> Void
    let onPan: (CGPoint, UIGestureRecognizer.State) -> Void
    let onScroll: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onRightTap: onRightTap, onPan: onPan, onScroll: onScroll)
    }

    func makeUIView(context: Context) -> TrackpadSurfaceView {
        let view = TrackpadSurfaceView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: TrackpadSurfaceView, context: Context) {}

    final class Coordinator: NSObject, TrackpadSurfaceDelegate {
        let onTap: (Int) -> Void
        let onRightTap: () -> Void
        let onPan: (CGPoint, UIGestureRecognizer.State) -> Void
        let onScroll: (CGPoint) -> Void

        init(
            onTap: @escaping (Int) -> Void,
            onRightTap: @escaping () -> Void,
            onPan: @escaping (CGPoint, UIGestureRecognizer.State) -> Void,
            onScroll: @escaping (CGPoint) -> Void
        ) {
            self.onTap = onTap
            self.onRightTap = onRightTap
            self.onPan = onPan
            self.onScroll = onScroll
        }

        func trackpadSurface(_ surface: TrackpadSurfaceView, didTapWithCount count: Int) {
            onTap(count)
        }

        func trackpadSurfaceDidRightTap(_ surface: TrackpadSurfaceView) {
            onRightTap()
        }

        func trackpadSurface(_ surface: TrackpadSurfaceView, panChangedBy translation: CGPoint, state: UIGestureRecognizer.State) {
            onPan(translation, state)
        }

        func trackpadSurface(_ surface: TrackpadSurfaceView, didScrollBy delta: CGPoint) {
            onScroll(delta)
        }
    }
}
