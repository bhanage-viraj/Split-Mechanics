//
//  ListenerView.swift
//  The Cursed Room
//
//  Phase 6A — visual impairment overlay (vignette) plus a one-time dismissible
//  role popup. Blur is applied by GameplayView to the camera layer.
//

import SwiftUI

struct ListenerView: View {
    @State private var showRolePopup = true

    var body: some View {
        ZStack {
            vignette

            if showRolePopup {
                RoleRevealPopup(
                    roleTitle: "You are the Listener",
                    roleDescription: "You can hear the hidden world, but your vision is fading.",
                    onDismiss: { withAnimation(.easeOut(duration: 0.25)) { showRolePopup = false } }
                )
            }
        }
        .ignoresSafeArea()
    }

    private var vignette: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(0.35),
                Color.black.opacity(0.92),
                Color.black
            ]),
            center: .center,
            startRadius: 40,
            endRadius: 420
        )
        .ignoresSafeArea()
    }
}
