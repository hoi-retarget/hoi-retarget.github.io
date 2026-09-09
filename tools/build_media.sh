#!/usr/bin/env bash
# Rebuild every image and video asset under static/ from the source renders.
#
# Everything this script writes is stripped of metadata (-map_metadata -1 for
# video, a Pillow re-save for stills) because the upstream PDFs carry an author
# name and the encoders stamp their own version strings.
# See CLAUDE.md: no asset may reach static/ without passing through here.
#
# Usage: tools/build_media.sh [figures|videos|all]
set -euo pipefail

SITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG="${FFMPEG:-ffmpeg}"
command -v "$FFMPEG" >/dev/null || { echo "ffmpeg not found; set FFMPEG=/path/to/ffmpeg" >&2; exit 1; }

# Source renders live outside this repo, in the private working tree. Their
# paths are NOT hardcoded here: a public repo must not name private directories.
# Point WORKSPACE at that tree (or set the SRC_* vars directly), e.g.
#   WORKSPACE=~/<workspace> tools/build_media.sh
WORKSPACE="${WORKSPACE:-$(cd "$SITE/.." && pwd)}"
SRC_PAPER="${SRC_PAPER:-$WORKSPACE/paper/new_media}"
# Human/G1/H2 panels re-rendered behind ONE camera distance -- see §"camera".
SRC_FIXED="${SRC_FIXED:-$WORKSPACE/renders/fixed_camera}"
SRC_COMPARE="${SRC_COMPARE:-$WORKSPACE/renders/hoi_vs_omni}"
SRC_COLLAB="${SRC_COLLAB:-$WORKSPACE/renders/collaborative}"
SRC_DYN="${SRC_DYN:-$WORKSPACE/renders/dynamic_cells}"
SRC_MONO="${SRC_MONO:-$WORKSPACE/renders/monocular}"

IMG="$SITE/static/images"
VID="$SITE/static/videos"

# ---------------------------------------------------------------- helpers ---
have() { [[ -d "$1" ]] || { echo "  -- skipping, no source dir: $1" >&2; return 1; }; }

# enc <out> <inputs...> -- <filter_complex>
enc() {
  local out="$1"; shift
  local -a ins=()
  while [[ "$1" != "--" ]]; do ins+=(-i "$1"); shift; done
  shift
  mkdir -p "$(dirname "$out")"
  "$FFMPEG" -y -v error -nostdin "${ins[@]}" \
    -filter_complex "$1" \
    -map_metadata -1 -map_chapters -1 -an \
    -c:v libx264 -profile:v main -pix_fmt yuv420p -crf "${CRF:-26}" -preset slow \
    -movflags +faststart "$out"
  printf '  %-56s %s\n' "${out#$SITE/}" "$(du -h "$out" | cut -f1)"
}

# Lay N same-sized panels in a row, each scaled to $1 px. Panels are exact equal
# fractions of the frame, which is what lets the HTML label row line up.
hrow() {
  local n="$1" pw="$2" f=""
  for ((i = 0; i < n; i++)); do f+="[$i:v]fps=30,scale=$pw:$pw:flags=lanczos,setsar=1[v$i];"; done
  for ((i = 0; i < n; i++)); do f+="[v$i]"; done
  printf '%shstack=inputs=%s' "$f" "$n"
}

# Two rows of N panels: inputs are row-major (top row first).
hgrid2() {
  local n="$1" pw="$2" f="" i
  for ((i = 0; i < 2 * n; i++)); do f+="[$i:v]fps=30,scale=$pw:$pw:flags=lanczos,setsar=1[v$i];"; done
  for ((i = 0; i < n; i++)); do f+="[v$i]"; done; f+="hstack=inputs=$n[top];"
  for ((i = n; i < 2 * n; i++)); do f+="[v$i]"; done; f+="hstack=inputs=$n[bot];"
  printf '%s[top][bot]vstack=2' "$f"
}

# ---------------------------------------------------------------- figures ---
build_figures() {
  echo "== figures =="
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  # Rasterise: pdftoppm drops the PDF's author/producer fields.
  pdftoppm -png -r 150 -singlefile "$SRC_PAPER/summary.pdf" "$tmp/pipeline"

  python3 - "$tmp" "$IMG" "$SRC_PAPER" <<'PY'
import sys, pathlib
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
tmp, out, paper = (pathlib.Path(p) for p in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
for src, name, width in [(tmp / "pipeline.png", "pipeline.jpg", 2200),
                         (paper / "title.png",  "teaser.jpg",   2400)]:
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(out / name, "JPEG", quality=90, optimize=True, progressive=True)
    print(f"  static/images/{name:<16} {im.width}x{im.height}  "
          f"{(out / name).stat().st_size / 1e6:.2f} MB")
PY
}

# ----------------------------------------------------------------- videos ---
# The camera
# ----------
# Every Human/G1/H2 panel in SRC_FIXED was rendered at ONE camera distance
# (4.05 m). The recorder's default is per-subject -- 3.0 m for the G1, 4.05 m for
# the H2, 3.0 m for the human -- which pushes the taller robot back exactly far
# enough to fill the same fraction of frame, hiding the 1.32 m / 1.80 m
# difference the page is trying to show. Do not restack these against panels
# rendered at the stock distance; the sizes would no longer be comparable.

build_omomo() {
  have "$SRC_FIXED/omomo" || return 0
  echo "== OMOMO: human | G1 | H2 (one camera distance) =="
  for stem in sub1_largetable_026 sub1_plasticbox_038 sub3_monitor_021 \
              sub4_whitechair_015 sub8_smallbox_023; do
    enc "$VID/omomo/${stem}.mp4" \
      "$SRC_FIXED/omomo/${stem}__human.mp4" \
      "$SRC_FIXED/omomo/${stem}__g1.mp4" \
      "$SRC_FIXED/omomo/${stem}__h2.mp4" -- "$(hrow 3 512)"
  done
}

build_datasets() {
  echo "== other datasets: human | G1 | H2 =="
  if have "$SRC_FIXED/datasets"; then
    for label in dumbbell pillow side_table; do
      enc "$VID/datasets/${label}.mp4" \
        "$SRC_FIXED/datasets/${label}__human.mp4" \
        "$SRC_FIXED/datasets/${label}__g1.mp4" \
        "$SRC_FIXED/datasets/${label}__h2.mp4" -- "$(hrow 3 512)"
    done
  fi
  # Collaborative pairs keep their own renderer's framing: it solves distance
  # from the robot-to-robot separation, not the robot type, so it never had the
  # normalisation problem the fixed camera exists to fix.
  have "$SRC_COLLAB" || return 0
  for pair in "bigwaterbottle:36_bigwaterbottle__0_152" "toolbox:448_toolbox__0_190"; do
    IFS=: read -r label stem <<<"$pair"
    enc "$VID/datasets/${label}.mp4" \
      "$SRC_COLLAB/corole__${stem}__smplx_two.mp4" \
      "$SRC_COLLAB/corole__${stem}__g1_two.mp4" \
      "$SRC_COLLAB/corole__${stem}__two_h2.mp4" -- "$(hrow 3 512)"
  done
}

build_comparison() {
  have "$SRC_COMPARE" || return 0
  echo "== comparison: source | OmniRetarget | ours =="
  for stem in clothesstand__sub1_clothesstand_001 whitechair__sub10_whitechair_023; do
    enc "$VID/comparison/${stem#*__}.mp4" \
      "$SRC_COMPARE/${stem}__smplx.mp4" \
      "$SRC_COMPARE/${stem}__omniretarget.mp4" \
      "$SRC_COMPARE/${stem}__hoi_retarget.mp4" -- "$(hrow 3 512)"
  done
}

build_augmentation() {
  have "$SRC_FIXED/augmentation" || return 0
  echo "== augmentation: 5 scales, G1 over H2 =="
  for stem in sub16_largebox_029 sub14_woodchair_042; do
    local -a ins=()
    for tag in g1 h2; do
      for s in 0.25 0.50 1.00 1.25 1.50; do
        ins+=("$SRC_FIXED/augmentation/${stem}__x${s}__${tag}.mp4")
      done
    done
    enc "$VID/augmentation/${stem}.mp4" "${ins[@]}" -- "$(hgrid2 5 400)"
  done
}

build_refinement() {
  have "$SRC_DYN" || return 0
  echo "== dynamic refinement: kinematic | trajectory-opt | RL tracker =="
  # roll_hoi is 50 fps against the others' 30; hrow's per-input fps=30 resamples
  # by timestamp so the three panels stay in sync.
  for stem in sub2_woodchair_001 sub2_trashcan_012 sub10_whitechair_060 \
              sub10_largebox_053 sub1_suitcase_022 sub10_smallbox_009 \
              sub11_monitor_081; do
    local obj="${stem#*_}"; obj="${obj%%_*}"
    local d="$SRC_DYN/$obj/$stem"
    enc "$VID/refinement/${stem}.mp4" \
      "$d/${stem}__ref_hoi.mp4" "$d/${stem}__dyna_hoi.mp4" "$d/${stem}__roll_hoi.mp4" \
      -- "$(hrow 3 512)"
  done
}

build_monocular() {
  have "$SRC_MONO" || return 0
  echo "== monocular reconstruction (orangetable) =="
  # The capture is 1080x1920 portrait against the square renders; centre-crop it
  # to square so all four panels share one aspect. The face is blurred upstream.
  enc "$VID/monocular/orangetable.mp4" \
    "$SRC_MONO/capture_blurred.mp4" "$SRC_MONO/smplx.mp4" \
    "$SRC_MONO/kinematic_g1.mp4" "$SRC_MONO/dynamic_g1.mp4" \
    -- "[0:v]fps=30,crop=in_w:in_w:0:(in_h-in_w)/2,scale=400:400:flags=lanczos,setsar=1[v0];\
[1:v]fps=30,scale=400:400:flags=lanczos,setsar=1[v1];\
[2:v]fps=30,scale=400:400:flags=lanczos,setsar=1[v2];\
[3:v]fps=30,scale=400:400:flags=lanczos,setsar=1[v3];[v0][v1][v2][v3]hstack=inputs=4"
}

build_posters() {
  echo "== posters =="
  mkdir -p "$VID/posters"
  find "$VID" -name '*.mp4' -not -path '*/posters/*' -print0 |
    while IFS= read -r -d '' v; do
      "$FFMPEG" -y -v error -nostdin -ss 1.2 -i "$v" -vframes 1 \
        -map_metadata -1 -q:v 4 "$VID/posters/$(basename "${v%.mp4}").jpg"
    done
  # ffmpeg's mjpeg encoder stamps a `comment` naming its own version, and Pillow
  # carries info["comment"] through a plain re-save, so drop it explicitly.
  python3 - "$VID/posters" <<'PY'
import pathlib, sys
from PIL import Image
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.jpg")):
    with Image.open(p) as im:
        rgb = im.convert("RGB")
        rgb.info.pop("comment", None)
        rgb.save(p, "JPEG", quality=82, optimize=True)
print(f"  {len(list(pathlib.Path(sys.argv[1]).glob('*.jpg')))} posters, metadata scrubbed")
PY
}

build_videos() {
  build_omomo; build_datasets; build_comparison
  build_augmentation; build_refinement; build_monocular; build_posters
}

case "${1:-all}" in
  figures) build_figures ;;
  videos)  build_videos ;;
  all)     build_figures; build_videos ;;
  *) echo "usage: $0 [figures|videos|all]" >&2; exit 2 ;;
esac

echo
echo "static/ total: $(du -sh "$SITE/static" | cut -f1)"
