#!/bin/sh
# Encode a demo recording, upload it to R2 and add it to the site's media list.
#
#   tools/media/put.sh <recording.mov> <title> <caption> [--feature] [--milestone m5]
#   tools/media/put.sh <screenshot.png> <title> <caption> [--milestone m5]
#
# A .png or .jpg is a still: uploaded as it is (images/<hash>.<ext>), listed with "image" in
# place of a video; it is never the featured video.
# --feature makes it the video at the top of the site. --milestone puts it in that
# milestone's progress log (default m5, the current one; see GOAL.md). Run from the repo root,
# then commit site/public/media.json and deploy the site (make site), which builds the RSS feed
# with the video as an item.
set -eu
in=$1; title=$2; caption=$3; shift 3
feature=; milestone=m5
while [ $# -gt 0 ]; do
  case $1 in
    --feature) feature=--feature ;;
    --milestone) milestone=$2; shift ;;
    *) echo "put.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
list=site/public/media.json

case $in in
  *.png|*.PNG|*.jpg|*.JPG|*.jpeg)
    [ -z "$feature" ] || { echo "put.sh: a still can't be the featured video" >&2; exit 2; }
    ext=$(echo "${in##*.}" | tr '[:upper:]' '[:lower:]'); [ "$ext" = jpeg ] && ext=jpg
    type=image/png; [ "$ext" = jpg ] && type=image/jpeg
    hash=$(shasum -a 256 "$in" | cut -c1-16)
    key="images/$hash.$ext"
    npx -y wrangler@4 r2 object put "cairn-media/$key" --file "$in" --content-type "$type" --remote >/dev/null
    w=$(sips -g pixelWidth "$in" | awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$in" | awk '/pixelHeight/ {print $2}')
    jq --arg image "/m/$key" --arg title "$title" --arg caption "$caption" --arg milestone "$milestone" \
       --arg date "$(date +%Y-%m-%d)" --arg published "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg commit "$(git rev-parse --short HEAD)" \
       --argjson w "$w" --argjson h "$h" \
       '[{image: $image, title: $title, caption: $caption, date: $date, published: $published, commit: $commit,
          width: $w, height: $h, milestone: $milestone}] + .' "$list" > "$work/m.json"
    mv "$work/m.json" "$list"
    echo "uploaded /m/$key"
    exit 0 ;;
esac

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
jq --arg video "/m/$video" --arg poster "/m/$poster" --arg title "$title" --arg caption "$caption" --arg milestone "$milestone" \
   --arg date "$(date +%Y-%m-%d)" --arg published "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg commit "$(git rev-parse --short HEAD)" \
   --argjson w "${size%,*}" --argjson h "${size#*,}" --argjson d "$duration" \
   --argjson feature "$([ "$feature" = --feature ] && echo true || echo false)" \
   '[{video: $video, poster: $poster, title: $title, caption: $caption, date: $date, published: $published, commit: $commit,
      width: $w, height: $h, seconds: ($d | floor), feature: $feature, milestone: $milestone}]
    + (if $feature then map(if .video then .feature = false else . end) else . end)' "$list" > "$work/m.json"
mv "$work/m.json" "$list"
echo "uploaded /m/$video ($(du -h "$work/v.mp4" 2>/dev/null | cut -f1 || true))"
