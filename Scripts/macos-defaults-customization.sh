#!/bin/bash

# Tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -int 1
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -int 1

# Three finger drag
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -int 1
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -int 1

# Sensitivity
defaults write NSGlobalDomain com.apple.trackpad.scaling -int 1

echo "✅ Trackpad configured"

# Key repeat rate (how fast keys repeat once started)
# Lower = faster. Range: 0 (fastest) to 120 (slowest)
# Default: 6
defaults write -g KeyRepeat -int 1

# Initial key repeat delay (how long to hold before repeating starts)
# Lower = shorter delay. Range: 15 (shortest) to 120 (longest)
# Default: 25
defaults write -g InitialKeyRepeat -int 15

echo "✅ Key repeat speed configured"

# Tab navigation in dialogs
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2

# Set Dock to show instantly with no delay
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.2

# Restart Dock to apply changes
killall Dock

echo "Dock auto-hide delay removed!"

# Disable press and hold
defaults write com.todesktop.230313mzl4w4u92 ApplePressAndHoldEnabled -bool false
