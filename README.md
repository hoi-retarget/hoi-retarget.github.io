# HOI-Retarget — project page

Source for <https://hoi-retarget.github.io/>.

Static site: `index.html` plus `static/`. No build step, no framework, no
package manager. GitHub Pages serves it from `main`.

> **This repo is anonymized for double-blind review (ICRA 2027).**
> Read [`CLAUDE.md`](CLAUDE.md) before changing anything. Nothing that could
> identify an author or their institution may enter this repository — including
> file metadata and the git history.

## Layout

```
index.html                 the entire page
static/css/index.css       project styles (Bulma is vendored template code)
static/js/index.js         clip switching + viewport-gated playback, no deps
static/images/             figures, rasterized from the paper's vector sources
static/videos/             side-by-side result clips
static/videos/posters/     poster frame for each clip
tools/build_media.sh       regenerates everything under static/
```

## Regenerating media

Every asset is produced by `tools/build_media.sh` — nothing is copied into
`static/` by hand. The script re-encodes and strips metadata, which is the point:
the upstream figure sources carry an author name in their document info.

It reads from the private render tree, whose location is deliberately not
hardcoded here:

```bash
WORKSPACE=/path/to/render/tree tools/build_media.sh all
# or point the three inputs individually:
SRC_PAPER=... SRC_JOB5=... SRC_TRIP=... tools/build_media.sh all
# subcommands: figures | videos | all
```

Needs `ffmpeg` (set `FFMPEG=` if it is not on `PATH`), `pdftoppm`, and Pillow.

## Before pushing

Run the anonymity audit. It lives **outside** this repo, because a list of the
identifiers you are suppressing is itself identifying:

```bash
~/.config/hoi-retarget/check_anonymity.sh .
```

A clean run is necessary, not sufficient — it only knows the patterns it was
given. Look at new figures and videos yourself for burned-in text: labels,
watermarks, UI chrome, wall-clock numbers, file paths.

## Still to do

- [ ] **Paper / arXiv / code / dataset links** — the four header buttons are
      inert `is-ghost` spans. Swap each for a real `<a href>` after the
      anonymity period.
- [ ] **Dataset download** — format, fields, licence, loader snippet.

### Camera framing — read before adding a Human/G1/H2 panel

Every panel in the OMOMO, other-datasets and augmentation sections is rendered at
**one camera distance (4.05 m)**. The recorder's default is per-subject —
`VIEWER_CAM_DISTANCE_DICT[robot] × 1.5` gives the G1 3.0 m and the H2 4.05 m, and
the SMPL renderer hardcodes 3.0 m — which pushes the taller robot back exactly far
enough to fill the same fraction of frame. That normalises away the 1.32 m /
1.80 m height difference these sections exist to show. `build_media.sh` documents
the fix; do not restack these against panels rendered at the stock distance.

Two sections deliberately opt out:

- **The OmniRetarget comparison** scales the human to the robot's object size so
  the contact comparison is like-for-like. Its subjects read slightly larger.
- **The collaborative clips** use a two-actor renderer whose distance comes from
  the robot-to-robot separation, not the robot type, so they never had the bug.

## Credits

Built on the [Nerfies](https://github.com/nerfies/nerfies.github.io) project
page template, used under
[CC BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/).
