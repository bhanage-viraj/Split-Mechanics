//
//  CurseBeginsView.swift
//  The Cursed Room
//
//  Phase 5 — full-screen black transition shown immediately after the doll
//  is touched. Both players see this before role assignment (Phase 6A).
//

import SwiftUI

struct CurseBeginsView: View {
    let onContinue: () -> Void

    @State private var didContinue = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.red.opacity(0.85))
                    .symbolEffect(.pulse)

                Text("The Curse Begins")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("Your senses have been separated.\nWork together to break the curse.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .onAppear {
            guard !didContinue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard !didContinue else { return }
                didContinue = true
                onContinue()
            }
        }
    }
}

#Preview {
    CurseBeginsView(onContinue: {})
}
