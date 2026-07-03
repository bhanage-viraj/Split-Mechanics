//
//  SeerView.swift
//  The Cursed Room
//
//  Phase 6A — clean AR feed with a role prompt for the Seer.
//

import SwiftUI

struct SeerView: View {
    var body: some View {
        VStack {
            roleBanner
            Spacer()
        }
        .padding()
    }

    private var roleBanner: some View {
        Text("You are the Seer. You can see the hidden world, but you cannot hear it.")
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.55))
            )
            .padding(.top, 8)
    }
}
