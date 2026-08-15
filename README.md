# bonfire

A bonfire that burns down over half an hour. Tap to feed it. Fullscreen it and leave it going.

Live: https://vaibhavkumar.is-a.dev/bonfire/

Single file, no build step, no CDN, no assets. Everything (the flame, the logs, the crackling) is generated at runtime.

## Controls

| | |
|---|---|
| tap or click anywhere | feed the fire: brighter, bigger, a crackle and a burst of sparks |
| drag the left edge | invisible slider, sets the fire anywhere from out to full blaze |
| lock button / `L` | freeze the fire where it is, so it stops burning down |
| speaker button / `S` | sound on-off |
| expand button / `F` / double-click | fullscreen |

The controls and the cursor fade out after ~2.6s of no input, so a fullscreen tab is just fire. The slider rail is invisible until you touch it, then fades again.

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
