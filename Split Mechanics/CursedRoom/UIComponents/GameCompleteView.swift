//
//  GameCompleteView.swift
//  The Cursed Room
//
//  Shown when the blood pool puzzle is solved (demo ends here for now).
//

import SwiftUI

struct GameCompleteView: View {
    let onContinue: () -> Void

    @State private var didContinue = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue.opacity(0.9))
                    .symbolEffect(.pulse)

                Text("The First Seal")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("The ancient fragment has been revealed.\nThe curse weakens… for now.")
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
    GameCompleteView(onContinue: {})
}
