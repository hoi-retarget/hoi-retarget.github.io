#!/usr/bin/env bash
# Rebuild every image and video asset under static/ from the source renders.
#
# Everything this script writes is stripped of metadata (-map_metadata -1 for
# video, re-encode for stills) because the upstream PDFs carry an author name.
# See CLAUDE.md: no asset may reach static/ without passing through here.
#
# Usage: tools/build_media.sh [figures|videos|all]
set -euo pipefail

SITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG="${FFMPEG:-ffmpeg}"
command -v "$FFMPEG" >/dev/null || { echo "ffmpeg not found; set FFMPEG=/path/to/ffmpeg" >&2; exit 1; }
# Source renders live outside this repo, in the private working tree. Their
# paths are NOT hardcoded here: a public repo must not name private directories.
# Point WORKSPACE at that tree (or set the three SRC_* vars directly), e.g.
#   WORKSPACE=~/<workspace> tools/build_media.sh
WORKSPACE="${WORKSPACE:-$(cd "$SITE/.." && pwd)}"
SRC_PAPER="${SRC_PAPER:-$WORKSPACE/paper/new_media}"
SRC_JOB5="${SRC_JOB5:-$WORKSPACE/renders/omomo_h2_augmentation_omni_compare}"
SRC_TRIP="${SRC_TRIP:-$WORKSPACE/renders/dynamic_refinement_triptychs}"

for d in "$SRC_PAPER" "$SRC_JOB5" "$SRC_TRIP"; do
  [[ -d "$d" ]] || { echo "missing source dir: $d" >&2
                     echo "set WORKSPACE, or SRC_PAPER/SRC_JOB5/SRC_TRIP, to the render tree" >&2
                     exit 1; }
done

IMG="$SITE/static/images"
VID="$SITE/static/videos"
mkdir -p "$IMG" "$VID"/{comparison,omomo,datasets,augmentation,refinement,posters}

# ---------------------------------------------------------------- helpers ---
# enc <out> <inputs...> -- <filter_complex> : encode web-safe h264, no metadata
enc() {
  local out="$1"; shift
  local -a ins=()
  while [[ "$1" != "--" ]]; do ins+=(-i "$1"); shift; done
  shift
  "$FFMPEG" -y -v error -nostdin "${ins[@]}" \
    -filter_complex "$1" \
    -map_metadata -1 -map_chapters -1 -an \
    -c:v libx264 -profile:v main -pix_fmt yuv420p -crf "${CRF:-26}" -preset slow \
    -movflags +faststart "$out"
  printf '  %-58s %s\n' "${out#$SITE/}" "$(du -h "$out" | cut -f1)"
}

# poster <video> : grab a mid-clip frame as the video's poster image
poster() {
  local v="$1" name
  name="$(basename "${v%.mp4}")"
  local dur; dur=$("$FFMPEG" -v error -i "$v" -f null - 2>&1 >/dev/null || true)
  "$FFMPEG" -y -v error -nostdin -ss 1.2 -i "$v" -vframes 1 \
    -map_metadata -1 -q:v 4 "$VID/posters/$name.jpg"
}

# hstack N panels of the same size, each scaled to $PW wide
hstack_filter() {
  local n="$1" pw="$2" f=""
  for ((i = 0; i < n; i++)); do f+="[$i:v]scale=$pw:$pw:flags=lanczos,setsar=1[v$i];"; done
  for ((i = 0; i < n; i++)); do f+="[v$i]"; done
  f+="hstack=inputs=$n"
  printf '%s' "$f"
}

# ---------------------------------------------------------------- figures ---
build_figures() {
  echo "== figures =="
  # Vector sources -> raster. pdftoppm drops the PDF's author/producer fields.
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN

  pdftoppm -png -r 150 -singlefile "$SRC_PAPER/summary.pdf"       "$tmp/pipeline"
  pdftoppm -png -r 200 -singlefile "$SRC_PAPER/hoivsomni.pdf"     "$tmp/hoi_vs_omni"
  pdftoppm -png -r 200 -singlefile "$SRC_PAPER/hoivsomnizoom.pdf" "$tmp/hoi_vs_omni_zoom"
  pdftoppm -png -r 150 -singlefile "$SRC_PAPER/augmentation.pdf"  "$tmp/augmentation"

  # width, quality: figures are 3D renders on soft gradients, JPEG holds up well.
  python3 - "$tmp" "$IMG" "$SRC_PAPER" <<'PY'
import sys, pathlib
from PIL import Image

tmp, out, paper = (pathlib.Path(p) for p in sys.argv[1:4])
JOBS = [
    (tmp / "pipeline.png",           "pipeline.jpg",        2200),
    (tmp / "hoi_vs_omni.png",        "hoi_vs_omni.jpg",     1600),
    (tmp / "hoi_vs_omni_zoom.png",   "hoi_vs_omni_zoom.jpg",1600),
    (tmp / "augmentation.png",       "augmentation.jpg",    2200),
    (paper / "title.png",            "teaser.jpg",          2400),
    (paper / "diverse.png",          "diverse.jpg",         2400),
]
for src, name, width in JOBS:
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    # save() with no exif/icc argument writes neither -> metadata is dropped
    im.save(out / name, "JPEG", quality=90, optimize=True, progressive=True)
    print(f"  static/images/{name:<24} {im.width}x{im.height}  "
          f"{(out / name).stat().st_size / 1e6:.2f} MB")
PY
}

# ----------------------------------------------------------------- videos ---
build_videos() {
  echo "== comparison: source | OmniRetarget | ours =="
  local E="$SRC_JOB5/E_hoi_vs_smplx_vs_omniretarget"
  for stem in clothesstand__sub1_clothesstand_001 whitechair__sub10_whitechair_023; do
    enc "$VID/comparison/${stem#*__}.mp4" \
      "$E/${stem}__smplx.mp4" "$E/${stem}__omniretarget.mp4" "$E/${stem}__hoi_retarget.mp4" \
      -- "$(hstack_filter 3 512)"
  done

  echo "== omomo: source | G1 | H2 =="
  local A="$SRC_JOB5/A_g1_omomo_results" B="$SRC_JOB5/B_h2_omomo_results"
  for stem in largetable__sub1_largetable_026 plasticbox__sub1_plasticbox_038 \
              monitor__sub3_monitor_021 whitechair__sub4_whitechair_015 \
              smallbox__sub8_smallbox_023; do
    enc "$VID/omomo/${stem#*__}.mp4" \
      "$A/${stem}__smplx.mp4" "$A/${stem}__g1.mp4" "$B/${stem}__h2.mp4" \
      -- "$(hstack_filter 3 512)"
  done

  echo "== other datasets: source | G1 =="
  local C="$SRC_JOB5/C_g1_diverse_datasets"
  for pair in \
    "imhd__dumbbell__20231014_dujsh_dumbbell_dumbbell_right_lunges1_0_0__550_880:dumbbell:" \
    "neuraldome__pillow__subject03_pillow_1245__0_330:pillow:" \
    "humoto__side_table__carry_side_table_with_both_hands_walk_ar_side_table__0_313:side_table:" \
    "corole__36_bigwaterbottle__0_152:bigwaterbottle:_two" \
    "corole__448_toolbox__0_190:toolbox:_two"; do
    IFS=: read -r stem name sfx <<<"$pair"
    enc "$VID/datasets/${name}.mp4" \
      "$C/${stem}__smplx${sfx}.mp4" "$C/${stem}__g1${sfx}.mp4" \
      -- "$(hstack_filter 2 512)"
  done

  echo "== augmentation: x0.25 .. x1.50 on G1 =="
  local D="$SRC_JOB5/D_h2_object_size_augmentation"
  for stem in largebox__sub16_largebox_029 whitechair__sub10_whitechair_028 \
              woodchair__sub14_woodchair_042; do
    enc "$VID/augmentation/${stem#*__}.mp4" \
      "$D/${stem}__x0.25__g1.mp4" "$D/${stem}__x0.50__g1.mp4" "$D/${stem}__x1.00__g1.mp4" \
      "$D/${stem}__x1.25__g1.mp4" "$D/${stem}__x1.50__g1.mp4" \
      -- "$(hstack_filter 5 400)"
  done

  echo "== dynamic refinement (pre-composited triptychs) =="
  for stem in sub1_clothesstand_001 sub10_whitechair_028 sub1_largetable_002 \
              trashcan_aug250_refined; do
    enc "$VID/refinement/${stem}.mp4" "$SRC_TRIP/${stem}.mp4" \
      -- "[0:v]scale=1440:-2:flags=lanczos,setsar=1"
  done

  echo "== posters =="
  find "$VID" -name '*.mp4' -not -path '*/posters/*' -print0 |
    while IFS= read -r -d '' v; do poster "$v"; done
  # ffmpeg's mjpeg encoder stamps a `comment` tag naming its own version. Harmless
  # in itself, but nothing leaves this build carrying tool provenance, so re-save
  # each poster through PIL, which writes no metadata block at all.
  python3 - "$VID/posters" <<'SCRUB'
import pathlib, sys
from PIL import Image
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.jpg")):
    with Image.open(p) as im:
        rgb = im.convert("RGB")
        # Pillow propagates info["comment"] into the saved COM marker, so a plain
        # re-save keeps ffmpeg's encoder string. Drop it explicitly.
        rgb.info.pop("comment", None)
        rgb.save(p, "JPEG", quality=82, optimize=True)
SCRUB
  echo "  $(ls "$VID/posters" | wc -l) posters written, metadata scrubbed"
}

case "${1:-all}" in
  figures) build_figures ;;
  videos)  build_videos ;;
  all)     build_figures; build_videos ;;
  *) echo "usage: $0 [figures|videos|all]" >&2; exit 2 ;;
esac

echo
echo "static/ total: $(du -sh "$SITE/static" | cut -f1)"
