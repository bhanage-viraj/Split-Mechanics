//
//  SeerView.swift
//  The Cursed Room
//
//  Phase 6A — clean AR feed with a one-time dismissible role popup.
//

import SwiftUI

struct SeerView: View {
    @State private var showRolePopup = true

    var body: some View {
        ZStack {
            if showRolePopup {
                RoleRevealPopup(
                    roleTitle: "You are the Seer",
                    roleDescription: "You can see the hidden world, but you cannot hear it.",
                    onDismiss: { withAnimation(.easeOut(duration: 0.25)) { showRolePopup = false } }
                )
            }
        }
    }
}
