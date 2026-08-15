# bonfire

A bonfire that burns down over half an hour. Tap to feed it. Fullscreen it and leave it going.

Live: https://vaibhavkumar.is-a.dev/bonfire/

Single file, no build step, no CDN, no assets. Everything (the flame, the logs, the crackling) is generated at runtime.

## Controls

| | |
|---|---|
| tap or click anywhere | feed the fire: brighter, bigger, a crackle and a burst of sparks |
| drag or scroll the **left half** | flame and brightness, from out to full blaze |
| drag or scroll the **right half** | volume, from silent to full |
| lock button / `L` | freeze the fire where it is, so it stops burning down |
| speaker button / `S` | sound on-off |
| expand button / `F` / double-click | fullscreen |

The whole screen is the control surface, split down the middle. A drag is a drag once it has travelled 8px; anything shorter is a tap and feeds the fire instead. Full range is 60% of the screen height, measured relative to where the drag started, so you can begin anywhere. Mouse wheel and trackpad scroll do the same thing on the same two halves.

Nothing is visible until you use it: a thin rail fades in on whichever side you are working and fades back out. The controls and the cursor fade out after ~2.6s of no input, so a fullscreen tab is just fire.

Sound starts muted because browsers block audio until you interact with the page. The first tap turns it on.

## Burning down

Left alone the fire goes from full to out in 30 minutes. The flames give out a little before the fuel does, so the last few minutes are a low fire sunk into the pyre, then the pyre goes dark and only embers keep lifting off the coals. Tapping brings it back: about eight taps take it from dead to full.

The flame does not just dim. As the fuel drops the fire narrows, its bed shrinks, the light it throws pulls in close instead of staying a wide dim wash, and the crackles get quieter and further apart. Height falls off far more slowly than width, otherwise the last flames hide inside the logs and it reads as coals long before it should.

One detail worth knowing: additive particle brightness falls off with roughly the square of the particle count, so emission scales as `fl^0.4` rather than linearly. A small fire is still locally bright, just smaller. Scaling emission linearly makes a half-fuel fire look nearly dead.

## What's in it

**Fire.** Three emitters at the base of the pyre feed a pooled particle system. Each particle gets buoyancy that decays as it cools, two octaves of value noise scrolling upward (the eddies that make flame look like flame), and a pull back toward the core so the column necks in above the logs. Particles are drawn additively from twelve pre-rendered colour sprites: white-hot at birth, deep red by the time they die. A separate short-lived "core" class burns white inside the pile; body particles never do, which is what keeps the middle from blowing out to a white blob.

**Everything else.** Coal bed with per-ember pulsing, logs with sawn end grain and glowing cracks that breathe on their own clocks, gravel and ash on the pit floor, embers that arc and flicker out, a thin lit smoke column, and a bloom pass over the top.

**Wandering.** A slow noise-driven gust and a slow intensity swell mean the fire never settles into a loop. Nothing here is on a fixed cycle.

**Crackles.** No bed, no roar, no hiss: silence between crackles. Each pop is a burst of a shared brown-noise buffer through a randomised bandpass with a fast exponential decay, and loud snaps get a woody triangle thump underneath. Crackle events are scheduled in simulation time, not by the audio clock, so the spark burst and the pop always agree and the sparks still fire when muted.

The timing is a clustered point process rather than a metronome. A log pops, then follows up with probability 0.45 about a second later, which makes cluster size geometric. Between clusters the gap is **log-normal** (median 12s, sigma 1.5), and that is the part that matters: a plain Poisson process has memoryless gaps but an exponential tail, so it would essentially never go quiet for minutes. Log-normal does. Measured over 200k draws at full fire:

| | gap |
|---|---|
| median | 2.2s |
| mean | 20s |
| 90th percentile | 47s |
| over 1 minute | 7.8% |
| over 3 minutes | 2.0% |
| over 5 minutes | 0.9% |

A dying fire stretches all of that by up to 4.5x. Feeding the fire cancels any long silence that was drawn while it was nearly dead.

Crackle timing has its own PRNG stream seeded from `crypto.getRandomValues`, so no two visits hear the same pattern. The screenshot hook re-seeds it to a fixed value so shots stay reproducible.

## Running for hours

- Fixed particle pools. Nothing allocates after startup.
- Fixed timestep with a clamp, so a backgrounded tab, a closed lid, or one stalled frame can never dump hours of simulation into a single step.
- Coming back from a hidden tab resets the clock instead of catching up.
- Audio nodes for a pop are created, played, and released. Only the noise buffer is long-lived.
- If the frame rate drops below ~42fps for two seconds the particle budget thins out, and recovers when there is headroom.
- Screen Wake Lock is requested where supported, otherwise a phone locks long before the 30 minutes are up.

## On iPhone

iPhone Safari has no element fullscreen, so the fullscreen button hides itself there. Add it to the home screen instead (`apple-mobile-web-app-capable` is set) and it opens without browser chrome.

Note that a web page cannot raise the hardware backlight. Tapping raises the light the fire itself puts out, which is what actually changes the pixels.

## Screenshot hook

Headless Chrome's virtual time never advances rAF properly, so there is a hook that steps the simulation directly and renders one deterministic frame, no rAF involved:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --use-angle=swiftshader \
  --window-size=1280,800 --virtual-time-budget=5000 \
  --screenshot=shot.png \
  "file:///path/to/bonfire/index.html#t=20&f=0.3"
```

`#t=<seconds>` (max 120) seeds a deterministic run, `&f=<0..1>` sets the fuel level and holds it there for the shot. Same window size, same frame, every time.
