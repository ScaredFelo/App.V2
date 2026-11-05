import SwiftUI
import UIKit

enum KeyboardDismiss {
    static func hide() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    KeyboardDismiss.hide()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Ocultar teclado")
            }
        }
    }
}

extension View {
    func withKeyboardDismiss() -> some View {
        modifier(KeyboardDismissModifier())
    }

    func dismissKeyboardOnTap() -> some View {
        background(KeyboardTapDismissView())
    }
}

private struct KeyboardTapDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = KeyboardTapHostView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            if let window {
                coordinator?.attach(to: window)
            } else {
                coordinator?.detach()
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow) {
            guard self.window !== window || recognizer == nil else { return }

            if let recognizer, let currentWindow = self.window {
                currentWindow.removeGestureRecognizer(recognizer)
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            self.recognizer = recognizer
            self.window = window
        }

        func detach() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }

            recognizer = nil
            window = nil
        }

        @objc private func handleTap() {
            KeyboardDismiss.hide()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !Self.isTextInput(touch.view)
        }

        private static func isTextInput(_ view: UIView?) -> Bool {
            var current = view

            while let candidate = current {
                if candidate is UITextField || candidate is UITextView {
                    return true
                }
                current = candidate.superview
            }

            return false
        }
    }
}

private final class KeyboardTapHostView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
