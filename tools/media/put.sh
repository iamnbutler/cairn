#!/bin/sh
# Encode a demo recording, upload it to R2 and add it to the site's media list.
#
#   tools/media/put.sh <recording.mov> <title> <caption> [--feature]
#
# --feature makes it the video at the top of the site. Run from the repo root,
# then commit site/public/media.json and deploy the site (make site).
set -eu
in=$1; title=$2; caption=$3; feature=${4:-}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ffmpeg -v error -y -i "$in" -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -movflags +faststart -an "$work/v.mp4"
ffmpeg -v error -y -i "$work/v.mp4" -frames:v 1 -q:v 3 "$work/p.jpg"

hash=$(shasum -a 256 "$work/v.mp4" | cut -c1-16)
video="videos/$hash.mp4"; poster="videos/$hash.jpg"
for pair in "$work/v.mp4:$video:video/mp4" "$work/p.jpg:$poster:image/jpeg"; do
  file=${pair%%:*}; rest=${pair#*:}; key=${rest%%:*}; type=${rest#*:}
  npx -y wrangler@4 r2 object put "cairn-media/$key" --file "$file" --content-type "$type" --remote >/dev/null
done

size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$work/v.mp4")
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/v.mp4")
list=site/public/media.json
jq --arg video "/m/$video" --arg poster "/m/$poster" --arg title "$title" --arg caption "$caption" \
   --arg date "$(date +%Y-%m-%d)" --arg commit "$(git rev-parse --short HEAD)" \
   --argjson w "${size%,*}" --argjson h "${size#*,}" --argjson d "$duration" \
   --argjson feature "$([ "$feature" = --feature ] && echo true || echo false)" \
   '[{video: $video, poster: $poster, title: $title, caption: $caption, date: $date, commit: $commit,
      width: $w, height: $h, seconds: ($d | floor), feature: $feature}]
    + (if $feature then map(.feature = false) else . end)' "$list" > "$work/m.json"
mv "$work/m.json" "$list"
echo "uploaded /m/$video ($(du -h "$work/v.mp4" 2>/dev/null | cut -f1 || true))"
