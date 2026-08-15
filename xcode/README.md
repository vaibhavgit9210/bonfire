# Bonfire, native

The same bonfire as `../index.html`, rebuilt as a real app. SwiftUI shell,
SpriteKit renderer, AVAudioEngine for the crackles. No packages, no assets,
nothing to fetch: open and run.

```
open xcode/Bonfire.xcodeproj
```

Pick **Bonfire** and a destination. One target builds for both:

| destination | notes |
|---|---|
| iPhone / iPad (device) | set your team under Signing & Capabilities first |
| iOS Simulator | no signing needed |
| My Mac | window is resizable, fullscreen button is in the corner |

Deployment targets are iOS 16 and macOS 13. Swift 5, no third-party code.

## What it does

Identical to the web build:

| | |
|---|---|
| tap anywhere | feed the fire: brighter, bigger, a crackle and a burst of sparks |
| drag the **left half** | flame and brightness |
| drag the **right half** | volume |
| scroll (Mac) | same two halves |
| lock button | freeze the fire where it is, so it stops burning down |
| speaker button | sound on-off |

Left alone the fire goes from full to out in 30 minutes, then only embers keep
lifting off the coals until you feed it. The screen is kept awake while the app
is in front, or the burn-down would be unwatchable on a phone.

## How it is put together

| file | |
|---|---|
| `Noise.swift` | mulberry32, value noise, Box-Muller, system entropy |
| `FireSim.swift` | the whole fire with no drawing in it |
| `SceneArt.swift` | Core Graphics: sprite textures, the pyre, the vignette |
| `FireScene.swift` | SpriteKit scene, node pools, input |
| `CrackleAudio.swift` | procedural pops, synthesised per crackle |
| `FireController.swift` | the only thing SwiftUI observes |
| `ContentView.swift` | rails and buttons over the scene |

Three things are worth knowing if you read the code.

**The simulation is a literal port.** Same constants, same order of random
draws, same `mulberry32`. Seeded identically, the Swift build and the web build
produce the same numbers. That was checked, not assumed: 960 steps at full fuel
and at 0.3 fuel give matching particle counts and matching position checksums to
four decimals in both. So if the fire ever looks wrong here, it is the renderer,
not the physics.

**Coordinates keep the web convention** inside the simulation: origin at the
middle of the pyre, y growing *downward*, so a rising particle has negative y.
`FireScene.place` flips the sign once when it positions a node. Keeping it that
way means the physics reads line for line against `index.html`.

**The pyre is drawn once and multiplied down.** The logs and ground are
rendered to a texture at full firelight, and each frame the node is tinted
toward black by `1 - light`, which SpriteKit's colour blend makes an exact
multiply. That is how the pyre dims as the fire dies without redrawing
anything. Everything additive (flames, sparks, coals, smoke, glow) shares one
white radial texture and is tinted per node, so SpriteKit batches it into very
few draw calls.

## Audio

Crackles only, no bed. Each one is synthesised on the spot: brown noise from a
four second buffer, resampled, through an RBJ bandpass, under an exponential
decay, with a woody thump added to the loud snaps. Six player nodes round-robin
so overlapping clusters mix instead of queueing behind each other.

On iOS the session category is `.ambient`, so it mixes with whatever else is
playing **and respects the ring switch**. If the phone is on silent there will
be no crackles. That is deliberate for a scenery app; change it to `.playback`
in `CrackleAudio.configureSession` if you would rather it ignore the switch.

Unlike the web build, sound starts **on** at 0.7. There is no autoplay policy to
work around here.

## Honest note on verification

This was written on a machine with only the Command Line Tools, no Xcode. So:

- every Swift file typechecks against the macOS SDK, and the simulation was
  compiled, run, and diffed against the web build (see above)
- `project.pbxproj` parses as a plist and its object graph was checked
  programmatically: no dangling references, all eight sources in the Sources
  phase, correct product type, Debug and Release present, and the shared scheme
  points at the real target UUID
- but it has **not** been opened in Xcode or put through `xcodebuild`, and the
  `#if os(iOS)` branches could not be typechecked without an iOS SDK

If the first build complains, it will almost certainly be something small in the
project settings rather than in the code.
