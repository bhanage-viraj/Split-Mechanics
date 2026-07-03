//
//  ListenerView.swift
//  The Cursed Room
//
//  Phase 6A — visual impairment overlay: vignette + role prompt on top of the
//  blurred AR feed (blur is applied by GameplayView to the camera layer).
//

import SwiftUI

struct ListenerView: View {
    var body: some View {
        ZStack {
            vignette
            rolePrompt
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

    private var rolePrompt: some View {
        VStack {
            Text("You are the Listener. You can hear the hidden world, but your vision is fading.")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.45))
                )
                .padding(.top, 8)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
