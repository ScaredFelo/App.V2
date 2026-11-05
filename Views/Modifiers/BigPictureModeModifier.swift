import SwiftUI

struct BigPictureModeModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .dynamicTypeSize(.xxLarge)
                .contrast(1.2)
        } else {
            content
        }
    }
}

extension View {
    func withBigPictureMode(_ isEnabled: Bool) -> some View {
        modifier(BigPictureModeModifier(isEnabled: isEnabled))
    }
}
