# CLAUDE.md — HOI-Retarget project page

Public GitHub Pages site for the HOI-Retarget paper, **submitted to ICRA 2027
under double-blind review**. Served at `https://hoi-retarget.github.io/`.

This repo is public and indexed. Treat everything in it as if a reviewer is
reading it with the express intent of identifying the authors.

---

## 1. The anonymity rule

> **Nothing that could identify an author, their institution, their funders, or
> their other work may enter this repository — not in the page, not in an asset,
> not in a filename, not in file metadata, and not in the git history.**

This overrides convenience, completeness, and every other instruction here. When
in doubt, leave it out and ask.

### Never appears anywhere in this repo

- Author names, initials, usernames, handles, ORCIDs, or email addresses.
- Institution or lab names, cities, campus names, logos, colour schemes, or fonts
  that are identifiably institutional.
- Funder, grant, or acknowledgement text.
- Links to personal or lab pages, personal GitHub/GitLab accounts, personal
  Google Drive / Dropbox / Hugging Face / W&B / YouTube / Vimeo links, or any
  other repo owned by an identifiable account.
- Analytics, tag managers, or any third-party beacon. The page must not phone
  home. (The Nerfies template ships a Google Analytics snippet — it has been
  removed and must not come back.)
- Cluster, hostname, filesystem-path, scheduler-account, or internal-tooling detail.
  Several source renders in the upstream workspace are debug dashboards with
  wall-clock budgets and job IDs burned into the frame; those are disqualified.
- Absolute paths from the author's machine (`/home/<user>/...`).
- Anything naming the upstream private repos or their branches.

### Always true of what does appear

- Authorship reads exactly `Anonymous Authors`.
- Venue reads `Under review, ICRA 2027`.
- The BibTeX entry has `author = {Anonymous}`.
- Every git commit is authored by the repo-local identity, never a personal one.

---

## 2. Metadata is the trap

Rendered assets carry identity even when the pixels do not.

- The upstream figure PDFs carry a real author name in their document-info
  dictionary (check with `pdfinfo`). Shipping one of those PDFs, or any PDF built
  from them, publishes that name. They are rasterized on the way in, which drops
  it — that is the whole reason the figures on this page are JPEG, not PDF.
- Images can carry EXIF/XMP; videos can carry `title`/`artist`/`comment` tags and
  an encoder string naming the source tool.
- Office/LaTeX-derived PDFs carry the author from the editor's profile.

**Therefore: no asset is copied into `static/` by hand.** Everything goes through
`tools/build_media.sh`, which re-encodes and strips metadata (`-map_metadata -1`
for video; for stills a Pillow re-save with `info["comment"]` explicitly dropped,
because Pillow otherwise carries ffmpeg's encoder string straight through). Add a
new source to that script and rerun it; do not `cp` into `static/`.

```bash
WORKSPACE=/path/to/render/tree tools/build_media.sh all
```

---

## 3. Before every commit

Run the audit and read its output:

```bash
~/.config/hoi-retarget/check_anonymity.sh .
```

**The auditor and its pattern list live outside this repo, and must stay there.**
A list of the identifiers you are suppressing is itself a list of the authors —
committing it would defeat the whole exercise. `.gitignore` blocks the obvious
places a copy would land; do not add one anyway.

It scans the working tree and the built assets for known identifiers (author
names, institution, lab, private infrastructure), checks media metadata, looks
for absolute home paths and third-party beacons, lists every external host the
page contacts, and verifies the git identity.

A clean run is necessary, not sufficient — it only knows the patterns it was
told about, and it cannot read pixels. Before adding any figure or video, look
at it yourself for burned-in text: labels, watermarks, UI chrome, wall-clock
numbers, job IDs, file paths, and recognisable faces or rooms.

---

## 4. Git identity

The repo carries a local identity; never rely on the global one:

```bash
git config user.name  "HOI-Retarget Anonymous"
git config user.email "hoi-retarget@users.noreply.github.com"
```

The audit fails if these drift. If a commit ever lands with the wrong author, it
must be rewritten and force-pushed — a public commit's author field is permanent
otherwise.

**Push identity — handled, keep it that way.** GitHub attributes the *push*
(visible in the repo's public Activity tab) to whichever account owns the SSH key,
independent of the commit author, so an anonymous commit author alone is not
enough. This repo pins a dedicated key via repo-local `core.sshCommand`, and that
key belongs to a separate, empty-profile GitHub account. The machine's default
key belongs to a personal account — never push this repo with it. Verify with:

```bash
ssh -i <the pinned key> -o IdentitiesOnly=yes -T git@github.com   # must NOT greet a personal login
```

---

## 5. Working on the page

- `index.html` is the whole site; there is no build step for the HTML.
- `static/css/index.css` holds the project styles; the Bulma files are vendored
  template code and should be left alone.
- `static/js/index.js` is hand-written, dependency-free. Do not add jQuery or a
  CDN script; every external request is a fingerprint and a liability.
- Google Fonts is the one external request the template makes. Keep it at that,
  or self-host the fonts.
- `tools/build_media.sh` regenerates every asset under `static/`. It reads from
  the private render tree via `$WORKSPACE`, which is deliberately not hardcoded —
  a public repo must not name private directories. It therefore only runs on a
  machine that has those renders; the built assets are committed so the site
  stands alone.
- Sections still carrying a `.placeholder` block are unfinished and marked as
  such in `README.md`. Do not quietly delete a placeholder — fill it or leave it.

## 6. Committing — show the author first

**Build it, screenshot it, and show the author locally before any commit or
push.** This page is a public artifact of a paper under review; the author
reviews changes before they go online, not after. This instruction stands until
they say otherwise.

Once they have signed off: run the audit, commit, push.

```bash
~/.config/hoi-retarget/check_anonymity.sh .   # must be CLEAN
```

To preview locally: `python3 -m http.server 8731` in the repo root.

Note that this differs from the surrounding private workspace, where commits are
the author's to make entirely. That rule still holds for every other repo.
