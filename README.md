# bonfire

A bonfire that burns forever in a browser tab. Fullscreen it, turn the sound on, leave it running.

Live: https://vaibhavkumar.is-a.dev/bonfire/

Single file, no build step, no CDN, no assets. Everything (the flame, the logs, the crackling) is generated at runtime.

## Controls

| | |
|---|---|
| click anywhere / speaker button / `S` | sound on-off |
| `F` / double-click / expand button | fullscreen |

The controls and the cursor fade out after ~2.6s of no input, so a fullscreen tab is just fire.

Sound starts muted because browsers block audio until you interact with the page.

## What's in it

**Fire.** Three emitters at the base of the pyre feed a pooled particle system. Each particle gets buoyancy that decays as it cools, two octaves of value noise scrolling upward (the eddies that make flame look like flame), and a pull back toward the core so the column necks in above the logs. Particles are drawn additively from twelve pre-rendered colour sprites: white-hot at birth, deep red by the time they die. A separate short-lived "core" class burns white inside the pile; body particles never do, which is what keeps the middle from blowing out to a white blob.

**Everything else.** Coal bed with per-ember pulsing, logs with sawn end grain and glowing cracks that breathe on their own clocks, gravel and ash on the pit floor, sparks that arc and flicker out, a thin lit smoke column, and a bloom pass over the top.

**Wandering.** A slow noise-driven gust and a slow intensity swell mean the fire never settles into a loop. Nothing here is on a fixed cycle.

**Crackles.** Crackle events are scheduled in simulation time, not by the audio clock, so the spark burst and the pop always agree, and the sparks still fire when muted. Each pop is a burst of the shared brown-noise buffer through a randomised bandpass with a fast exponential decay; loud snaps get a woody triangle thump underneath. The bed under it all is that same noise split into a low roar and a high hiss, modulated by three detuned sub-Hz LFOs.

## Running for hours

That was the point, so:

- Fixed particle pools. Nothing allocates after startup.
- Fixed timestep with a clamp, so a backgrounded tab, a closed lid, or one stalled frame can never dump hours of simulation into a single step.
- Coming back from a hidden tab resets the clock instead of catching up.
- Audio nodes for a pop are created, played, and released. Only the noise buffer and the bed are long-lived.
- If the frame rate drops below ~42fps for two seconds the particle budget thins out, and recovers when there is headroom.

## Screenshot hook

Headless Chrome's virtual time never advances rAF properly, so there is a hook that steps the simulation directly and renders one deterministic frame, no rAF involved:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --use-angle=swiftshader \
  --window-size=1280,800 --virtual-time-budget=4000 \
  --screenshot=shot.png \
  "file:///path/to/bonfire/index.html#t=20"
```

`#t=<seconds>` (max 120) seeds a deterministic run: same window size, same frame, every time.
