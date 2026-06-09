#!/usr/bin/env bash

# Exit if Spotify is not active
if ! playerctl -p spotify status >/dev/null 2>&1; then
    notify-send -u low -a "Music" "Spotify is not running"
    exit 0
fi

# Get metadata
title=$(playerctl -p spotify metadata xesam:title)
artist=$(playerctl -p spotify metadata xesam:artist)
album=$(playerctl -p spotify metadata xesam:album)
art_url=$(playerctl -p spotify metadata mpris:artUrl)

# Create a unique cover path under /tmp based on artUrl to avoid caching wrong covers
if [ -n "$art_url" ]; then
    # Generate a simple hash of the URL
    url_hash=$(echo -n "$art_url" | md5sum | cut -d' ' -f1)
    cover_path="/tmp/spotify_cover_${url_hash}.png"

    # Download only if the file doesn't exist yet
    if [ ! -f "$cover_path" ]; then
        curl -s -L "$art_url" -o "$cover_path"
    fi

    # Send notification with the downloaded cover as icon
    notify-send -a "Music" -i "$cover_path" "$title" "by $artist\nAlbum: $album"
else
    # Send notification without icon
    notify-send -a "Music" "$title" "by $artist\nAlbum: $album"
fi
