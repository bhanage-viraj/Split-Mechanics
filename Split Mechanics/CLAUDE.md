
# Cloud.md: The Cursed Room (AR Asymmetrical Co-Op)
**Project Blueprint & Architecture Specification**

---

## 1. Game Script & Core Gameplay Loop

This is the definitive flow of the game, mapping out the asymmetrical experience from the initial handshake to the final escape.

### Phase 1: The Setup
* **Story Introduction:** Both players receive a short storyline introducing the monster, explaining its origin, and revealing that it is haunting their house.
* **Room Scan:** Player A (Host) scans the real room to create a shared AR environment. The system runs benchmark checks to ensure the room is scanned perfectly. If the scan fails (e.g., walls are not mapped properly), a retry prompt appears.
* **Shared AR Space:** Both players enter the same AR version of the scanned room. In the center, they see the same mysterious doll. To prevent the doll from spawning in odd places (like under a table), an algorithm ensures it is placed strictly on the floor, away from walls and obstacles.
* **The Curse Begins:** Both players must physically touch the doll. Once touched, the curse is activated. A pop-up message explains that their senses have been separated randomly. Their mission is to break the curse by working together.

### Phase 2: Asymmetrical Investigation (Seal #1)
Players review their roles, abilities, and available equipment. Player A presses "Done" to begin.
* **Player A (The Seer):** Can see hidden supernatural clues through AR but cannot hear them. Their audio is replaced with static/white noise.
* **Player B (The Listener):** Can hear supernatural spatial audio cues but cannot see hidden objects.
* **Following the Sounds:** The game begins. The Seer follows the Listener. The Listener starts hearing distant supernatural sounds and guides both players through the room toward their source, combating potential audio direction confusion.
* **First Discovery:** When they reach the correct location, the Seer uses the phone's camera to reveal a hidden letter visible only in AR. (The letter is anchored to a scanned wall at a reachable height, never floating in the middle of space).
* **The Main Objective:** The letter reveals the mission: *"To break the curse, you must find the two pieces of the ancient seal. Only when the seal is restored will the monster lose its power."*

### Phase 3: Split Investigation (Seal #2)
* **The Clue & The Lock:** The Listener begins hearing a distant whisper or eerie chant. Moving closer makes the words clearer, revealing a riddle or clue containing a code. Meanwhile, the Seer discovers a trail of bloody footprints visible only in AR, leading to a hidden, locked supernatural mechanism on a wall or floor. 
* **Collaboration:** The players must communicate. The Listener shares the clue, and the Seer solves the puzzle, mapping the 2D lock mechanism to the AR environment.
* **First Seal Revealed:** After entering the correct code, the Seer reveals and collects the first piece of the ancient seal hidden inside the environment.

### Phase 4: The Frequency Puzzle (Seal #3)
* **The Frequency Match:** The Seer discovers another hidden AR clue leading to a new location, revealing a seemingly meaningless number mysteriously appearing on a wall or floor. 
* **The Scanner:** The players realize this number corresponds to a sound frequency. The Listener opens their Frequency Scanner (a device visualizing nearby sound frequencies). Moving through the room, they adjust their scanner to match the frequency the Seer found.
* **Second Seal Revealed:** When the Listener matches the frequency, an invisible mechanism activates. Only the Listener hears the deep sound of a massive stone button being pressed. The environment changes for the Seer, a hidden barrier disappears, and they collect the second seal.

### Phase 5: The Ritual & Escape
* **Returning to the Ritual Site:** The players must return to the location of the mysterious doll. Both players are guided back using haptic feedback—vibrations become stronger as they get closer to the ritual site.
* **Restoring the Seal:** Once both arrive, the Seer notices the doll has disappeared, revealing an ancient pedestal. Using their inventory, the Seer drags and places both seal pieces onto the pedestal.
* **The Curse is Broken:** The players receive a message: *"The curse has been broken."* Senses are restored. Player A can see and hear; Player B can hear and see.
* **Final Escape:** A countdown timer immediately appears. The monster has awakened. A safe zone appears in AR as a glowing circle on the floor. Both players must reach the safe zone together before the timer expires to survive and win. If either fails, the monster catches them (Game Over).

---

## 2. Architecture & Frameworks

The application utilizes a **VIPER (View, Interactor, Presenter, Entity, Router)** architecture integrated with SwiftUI to cleanly separate the complex AR and network states from the UI rendering.

| Framework | Purpose in Architecture |
| :--- | :--- |
| **ARKit** | Handles environment tracking, LiDAR scene reconstruction, and `isCollaborationEnabled` for merging the Host and Guest into the same physical coordinate space via `ARParticipantAnchor`. |
| **RealityKit** | Renders 3D entities (Doll, Seals, Footprints), manages physical collisions, and handles raycasting for object placement. |
| **MultipeerConnectivity** | The local network layer. Connects the Host and Guest via Wi-Fi/Bluetooth to sync lightweight game state events and the initial map data. |
| **PHASE** | (Physical Audio Spatialization Engine). Drives the Listener's spatial audio, calculating complex 3D audio occlusion and bouncing sounds off physical walls. |
| **CoreHaptics** | Provides distance-based physical feedback (rumble) to guide players to objectives or back to the ritual site. |

---

## 3. Formulas & Randomness

To ensure fair gameplay and precise alignment across devices, the game relies on strict mathematical frameworks rather than raw random number generation.

### Distance & Spatial Coordinates
To calculate how close a player is to a clue (for haptics or audio volume scaling), the game extracts the position vector from the camera's 4x4 matrix and calculates the Euclidean distance in 3D space.

$$d = \sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2 + (z_2 - z_1)^2}$$

### Frequency Puzzle & Audio Feedback
To prevent frustration when the Listener is dialing the frequency slider, the game applies a forgiveness tolerance and linear interpolation to crossfade static with the actual clue audio. Signal Clarity ($C$) is calculated as:

$$C = \max\left(0, 1 - \frac{|F_p - F_t|}{\text{HearingRange}}\right)$$

### Predetermination & Bounded Randomness
* **Predetermination:** To prevent network desync, the Host calculates all puzzle variables (frequencies, lock codes, spawn coordinates) exactly once during the setup phase and sends a single `GameStateSeed` to the Guest.
* **Marble Bag:** Frequencies are pulled from a pre-defined array of distinct acoustic values. Once used, a value is discarded to ensure auditory variety.
* **Bounded Randomness:** * *Clamping:* Clues spawned on walls have their Y-axis mathematically clamped to remain at eye level.
    * *Rejection Sampling:* Floor spawns are checked against wall coordinates. If $d < 0.5$ meters from a wall, the coordinate is rejected and rerolled to prevent the doll from clipping into physical furniture.

---

## 4. Bottlenecks & Fixes

### 1. The "Blank Wall" Relocalization Failure
* **Bottleneck:** The Host's LiDAR can map featureless white walls perfectly, but when the Guest (using optical tracking) tries to merge maps, it fails due to a lack of visual contrast.
* **Fix:** Implement point cloud validation during the benchmark phase. The Host's UI must refuse to finalize the scan unless it detects sufficient visual feature points, prompting the user to "Scan areas with distinct textures or furniture."

### 2. Audio Direction Inaccuracies
* **Bottleneck:** Spatial audio can sound flat or reversed if the Listener's virtual audio listener is not strictly bound to their device's physical orientation.
* **Fix:** Bind the `PHASEListener` directly to the `ARCamera` transform, ensuring real-world physical turns dynamically update the audio panning. Utilize haptic breadcrumbs as a fallback if the player becomes disoriented.

### 3. Asymmetrical State Desync
* **Bottleneck:** Transitioning between 2D UI puzzles and 3D AR scenes can cause the two devices to fall out of sync if both attempt to calculate win conditions independently.
* **Fix:** Maintain absolute authority. Only the player interacting with a puzzle calculates its state. Upon solving it, they dispatch a lightweight Remote Procedure Call (RPC) payload via MultipeerConnectivity to explicitly command the other device to update its state.
