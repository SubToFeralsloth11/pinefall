#!/usr/bin/env bash
# Downloads the CC0 Poly Haven assets used by the demo into assets/polyhaven.
# Assets are not committed (fir_tree_01.bin alone is ~480 MB).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=assets/polyhaven
API=https://api.polyhaven.com/files

# name:resolution
MODELS=(
  fir_tree_01:1k
  fir_sapling_medium:1k
  pine_sapling_small:2k
  fern_02:2k
  grass_medium_01:2k
  moss_01:2k
  pine_roots:1k
  dead_tree_trunk:2k
  rock_moss_set_01:2k
  rock_moss_set_02:2k
  dry_branches_medium_01:2k
  boulder_01:2k
)
HDRI=kloofendal_28d_misty_puresky:4k
GROUND=forrest_ground_01:2k

fetch() { # url dest
  [[ -s "$2" ]] && return 0
  mkdir -p "$(dirname "$2")"
  echo "  $2"
  curl -fsSL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"
}

for entry in "${MODELS[@]}"; do
  name=${entry%%:*}; res=${entry##*:}
  echo "model $name ($res)"
  json=$(curl -fsSL "$API/$name")
  dir=$OUT/models/$name
  fetch "$(jq -r --arg r "$res" '.gltf[$r].gltf.url' <<<"$json")" "$dir/$name.gltf"
  while IFS=$'\t' read -r rel url; do
    fetch "$url" "$dir/$rel"
  done < <(jq -r --arg r "$res" '.gltf[$r].gltf.include | to_entries[] | "\(.key)\t\(.value.url)"' <<<"$json")
done

name=${HDRI%%:*}; res=${HDRI##*:}
echo "hdri $name ($res)"
fetch "$(curl -fsSL "$API/$name" | jq -r --arg r "$res" '.hdri[$r].hdr.url')" "$OUT/hdri/$name.hdr"

name=${GROUND%%:*}; res=${GROUND##*:}
echo "texture $name ($res)"
json=$(curl -fsSL "$API/$name")
for map in Diffuse nor_gl Rough AO Displacement; do
  url=$(jq -r --arg m "$map" --arg r "$res" '.[$m][$r].jpg.url // .[$m][$r].png.url' <<<"$json")
  fetch "$url" "$OUT/textures/$name/$(basename "$url")"
done
echo done
