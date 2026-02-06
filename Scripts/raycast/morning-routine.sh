#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Morning Routine
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ☀️
# @raycast.packageName Utils

osascript -e 'set volume output volume 25'

osascript -e '
  tell application "Spotify"
    play track "spotify:album:5kBtLULy6vMwjFRSSEEIjP"
  end tell
  tell application "System Events"
    set visible of process "Spotify" to false
  end tell
'
