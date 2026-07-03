Prompt: Phase 6 - Role Assignment, Spatial Audio, and The Hunt

Role: You are an Expert iOS Developer specializing in SwiftUI, ARKit, RealityKit, and VIPER architecture.

Context: We are building an asymmetrical AR horror game called "The Cursed Room". We have completed the world merging (Phase 4/5). Both players have touched the Doll in the center of the room. We are now executing Phase 6, which assigns roles, blinds/deafens the players, and spawns the first hidden objective (The Letter).

Task: Please generate the code for Phase 6, broken down into manageable sub-tasks.

Phase 6A: Role Assignment & UI Overlays

Randomization Sync: The Host must generate a random boolean (e.g., isHostSeer = Bool.random()). Send this to the Guest via our NetworkService so both devices know exactly who is the Seer and who is the Listener.

Dummy UI Screens: Create two basic SwiftUI views for the transition:

SeerView: Displays "You are the Seer. You can see the hidden world, but you cannot hear it."

ListenerView: Displays "You are the Listener. You can hear the hidden world, but your vision is fading."

Listener Impairment (Vignette/Blur): On the ListenerView, overlay the ARViewContainer with a heavy blur and a dark vignette. Do not use complex CIFilters yet; use SwiftUI's .blur(radius: 20) combined with a RadialGradient (black on the edges, slightly transparent in the center) to simulate blindness.

Phase 6B: Spawning the Letter & RealityKit Spatial Audio

Safe Spawning (Far Away): Write a function in the ARService that looks at the current camera position and iterates through detected ARPlaneAnchors (vertical walls). Select a wall coordinate that is at least 2.0 meters away from the players. If no wall is that far, pick the furthest available wall.

The 3D Entity: Create an AnchorEntity at that far wall coordinate. Attach a simple RealityKit 3D plane/box to represent "The Letter".

Asymmetrical Rendering: * If Player is Listener: Set the Letter entity's .isEnabled = false (invisible). Load a looping audio resource (AudioFileResource.load) and play it from this entity using RealityKit's built-in spatial audio (entity.playAudio). Crucial: Rely entirely on RealityKit's automatic 3D distance/panning. Do not calculate attenuation manually.

If Player is Seer: Render the 3D Letter entity normally. Do NOT attach or play the audio resource.

Phase 6C: The Discovery

Proximity Check: In the Gameplay Interactor, run a 60fps check calculating the distance between the local camera (ARView.cameraTransform) and the Letter's 3D coordinates.

The Reveal: When the Seer is within 1.0 meter of the Letter, update the GameplayPresenter to display a 2D SwiftUI overlay reading:
"To break the curse, you must find the two pieces of the ancient seal. Only when the seal is restored will the monster lose its power."

Completion: Include a "Next" button on this message that sends a network event to both devices, readying them for Phase 7.

Requirements & Constraints:

VIPER Architecture: Keep the distance math in the Interactor, the AR/Audio spawning in the ARService, and the Overlays in the SwiftUI View.

Audio Setup: Remind me to include a dummy .mp3 or .wav file in my Xcode project bundle so AudioFileResource.load doesn't crash.

Please provide the updated Swift code for the ARService, GameplayInteractor, and the GameplayView/ListenerView.
