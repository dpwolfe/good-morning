#!/bin/bash

# THIS SETUP SCRIPT IS A WORK IN PROGRESS

# Install latest version of git

# Install node version manager
# https://github.com/creationix/nvm#install-script
if ! type "npm" > /dev/null; then
  echo "Installing NodeJS with Node Version Manager"
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.1/install.sh | bash
fi

# commands below pending fixes and integration above or simply deletion
# copy and manually run sections below for now
if false; then

# install homebrew - https://brew.sh
# todo: prompts to hit enter to continue and then your machine user password
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Install iTerm http://iterm2.com
curl -JL https://iterm2.com/downloads/stable/latest -o ~/Downloads/iTerm.zip
unzip -q ~/Downloads/iTerm.zip -d /Applications
rm ~/Downloads/iTerm.zip
# Install Fixed Solarized iTerm colors https://github.com/yuex/solarized-dark-iterm2
curl -JL "https://github.com/yuex/solarized-dark-iterm2/raw/master/Solarized%20Dark%20(Fixed).itermcolors" -o ~/Downloads/SolarizedFixed.itermcolors
# Set the iTerm buffer scroll back to unlimited, or some much larger number than 1000 in Settings > Profiles > Terminal
# Install the iTerm shell integrations from the File menu
# Add step to import that download
# Add step to select that color set

# install Mac App Store command line interface
# https://github.com/mas-cli/mas
brew install mas
# sign into the App Store
mas signin --dialog youremail@example.com
# upgrade any outdated applications
mas upgrade
# install shpotify, the spotify CLI
brew install shpotify

# Xcode - Install
mas install 497799835
xcode-select --install
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild  -license accept
sudo installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDevice.pkg -target /
sudo installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDeviceDevelopment.pkg -target /
sudo installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
# Xcode - Agree to license
sudo xcodebuild -license

# Install Magnet https://itunes.apple.com/us/app/magnet/id441258766
mas install 441258766
open /Applications/Magnet.app

# Install Slack https://itunes.apple.com/us/app/slack/id803453959
mas install 803453959

# Install OneDrive https://itunes.apple.com/us/app/onedrive/id823766827
mas install 823766827

# Install OmniFocus 2 - https://omnistaging.omnigroup.com/omnifocus-2/
curl https://omnistaging.omnigroup.com/omnifocus/releases/OmniFocus-2.9.x-r285656-Test.dmg -o ~/Downloads/OmniFocus.dmg
yes | hdiutil attach ~/Downloads/OmniFocus.dmg > /dev/null
sudo ditto /Volumes/OmniFocus/OmniFocus.app /Applications/OmniFocus.app
diskutil unmount OmniFocus
rm ~/Downloads/OmniFocus.dmg

# Install OmniOutliner 5 Preview https://omnistaging.omnigroup.com/omnioutliner/
curl https://omnistaging.omnigroup.com/omnioutliner/releases/OmniOutliner-5.0-r283820-Test.dmg -o ~/Downloads/OmniOutliner.dmg
yes | hdiutil attach ~/Downloads/OmniOutliner.dmg > /dev/null
sudo ditto /Volumes/OmniOutliner/OmniOutliner.app /Applications/OmniOutliner.app
diskutil unmount OmniOutliner
rm ~/Downloads/OmniOutliner.dmg

# Install iTerm http://iterm2.com
curl -JL https://iterm2.com/downloads/stable/latest -o ~/Downloads/iTerm.zip
unzip -q ~/Downloads/iTerm.zip -d /Applications
rm ~/Downloads/iTerm.zip
# Install Fixed Solarized iTerm colors https://github.com/yuex/solarized-dark-iterm2
curl -JL "https://github.com/yuex/solarized-dark-iterm2/raw/master/Solarized%20Dark%20(Fixed).itermcolors" -o ~/Downloads/SolarizedFixed.itermcolors
# Set the iTerm buffer scroll back to unlimited, or some much larger number than 1000 in Settings > Profiles > Terminal
# Install the iTerm shell integrations from the File menu
# Add step to import that download
# Add step to select that color set

# Install Google Chrome
curl -JL https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg -o ~/Downloads/googlechrome.dmg
hdiutil attach ~/Downloads/googlechrome.dmg
sudo ditto /Volumes/Google\ Chrome/Google\ Chrome.app /Applications/Google\ Chrome.app
diskutil unmount Google\ Chrome
rm ~/Downloads/googlechrome.dmg

# Install Office 365
curl -JL https://go.microsoft.com/fwlink/?linkid=532572 -o ~/Downloads/InstallOffice.pkg
sudo installer -pkg ~/Downloads/InstallOffice.pkg -target /
rm ~/Downloads/InstallOffice.pkg

# Install Spotify
curl -JL https://download.spotify.com/Spotify.dmg -o ~/Downloads/Spotify.dmg
hdiutil attach ~/Downloads/Spotify.dmg
sudo ditto /Volumes/Spotify/Spotify.app /Applications/Spotify.app
diskutil unmount Spotify
rm ~/Downloads/Spotify.dmg

# Install Docker
curl -JL https://download.docker.com/mac/stable/Docker.dmg -o ~/Downloads/Docker.dmg
hdiutil attach ~/Downloads/Docker.dmg
sudo ditto /Volumes/Docker/Docker.app /Applications/Docker.app
diskutil unmount Docker
rm ~/Downloads/Docker.dmg

# Install Dropbox https://www.dropbox.com/download?plat=mac
curl -JL https://www.dropbox.com/download?plat=mac -o ~/Downloads/InstallDropbox.dmg
hdiutil attach ~/Downloads/InstallDropbox.dmg
open /Volumes/Dropbox\ Installer/Dropbox.app

# Install Blue Jeans Launcher

# Install Charles
curl -JL https://www.charlesproxy.com/assets/release/4.1.1/charles-proxy-4.1.1.dmg -o ~/Downloads/InstallCharles.dmg
yes | hdiutil attach ~/Downloads/InstallCharles.dmg > /dev/null
sudo ditto /Volumes/Charles\ Proxy\ v4.1.1/Charles.app /Applications/Charles.app
diskutil unmount Charles\ Proxy\ v4.1.1
rm ~/Downloads/InstallCharles.dmg

# Install YubiKey PIV Manager to enable unlock with a YubiKey
curl -JL https://developers.yubico.com/yubikey-piv-manager/Releases/yubikey-piv-manager-1.4.1-mac.pkg -o ~/Downloads/InstallPIVManager.pkg
sudo installer -pkg ~/Downloads/InstallPIVManager.pkg -target /
rm ~/Downloads/InstallPIVManager.pkg

# System Configuration
# Dim icons on app bar for apps that were hidden with Command+H
defaults write com.apple.dock showhidden -bool true
# Only show icons of running apps in app bar, using Spotlight to launch
defaults write com.apple.dock static-only -bool TRUE
# Auto show and hide the dock
defaults write com.apple.dock autohide -bool true
# Make the auto show and hide for the dock happen immediately
defaults write com.apple.dock autohide-time-modifier -int 0
# Attach the dock to the left side, the definitive optimal location according to the community
defaults write com.apple.dock orientation left
# Enable tap to click on trackpad
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
# Bump up the trackpad speed a couple notches
defaults write -g com.apple.trackpad.scaling 2
# Turn off the annoying auto-capitalize while typing
defaults write -g NSAutomaticCapitalizationEnabled -bool false
# todo: disable siri
# enable the new settings in the dock without restarting
killall Dock
killall Finder
# set fast speed key repeat, setting to 0 basically deletes everything at once in some slower apps, 1 is still to fast for some apps
#d 2 is the reasonable safe min
defaults write NSGlobalDomain KeyRepeat -int 2
# set the delay until repeat to be very short
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Install GPG Suite
https://releases.gpgtools.org/GPG_Suite-2017.1b3-v2.dmg
curl https://releases.gpgtools.org/GPG_Suite-2017.1b3-v2.dmg -o ~/Downloads/GPGSuite.dmg
hdiutil attach ~/Downloads/GPGSuite.dmg
open /Volumes/GPG\ Suite/Install.pkg
# Silence output about needing a passphrase on each GPG commit
echo 'no-tty' >> ~/.gnupg/gpg.conf
# clone the bing desktop script
# schedule script for daily run
# todo: setup daily refresh script

# Install Python
brew install python

# Install AWS CLI
sudo pip install awscli

# Install Atom Beta
curl -JL https://atom.io/download/mac?channel=beta -o ~/Downloads/AtomBeta.zip
unzip -q ~/Downloads/AtomBeta.zip -d /Applications
rm ~/Downloads/AtomBeta.zip

# Install Atom
curl -JL https://atom.io/download/mac -o ~/Downloads/Atom.zip
unzip -q ~/Downloads/Atom.zip -d /Applications
rm ~/Downloads/Atom.zip
# install atom shell commands
# Install atom packages
apm install atom-typescript docblockr ex-mode file-icons git-plus git-time-machine highlight-selected jumpy last-cursor-position linter linter-eslint linter-shellcheck merge-conflicts nuclide prettier-atom project-manager set-syntax sort-lines split-diff vim-mode

# Generate a new SSH key for GitHub https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
# start ssh-agent
eval "$(ssh-agent -s)"
# automatically load the keys and store passphrases in your keychain
echo "Host *
 AddKeysToAgent yes
 UseKeychain yes
 IdentityFile ~/.ssh/id_rsa" > ~/.ssh/config
# add your ssh key to ssh-agent
ssh-add -K ~/.ssh/id_rsa
# copy public ssh key to clipboard for pasting on GitHub
pbcopy < ~/.ssh/id_rsa.pub
# open the GitHub key management page
open https://github.com/settings/keys
# click "New SSH key" and add the key
# generate a gpg key and add to GitHub https://help.github.com/articles/generating-a-new-gpg-key/
gpg --gen-key
# RSA & RSA, 1y recommended
gpg --list-secret-keys --keyid-format LONG
# copy the GPG public key for GitHub
gpg --armor --export paste-the-id-here | pbcopy
# open the GitHub key management page
open https://github.com/settings/keys
# click "New GPG key" and add the key
# enable autos-signing of all the commits
git config --global commit.gpgsign true

# setup .bash_profile
mkdir ~/repo && cd ~/repo
git clone git@github.com:dpwolfe/environment.git
echo "export REPO_ROOT=~/repo
source \$REPO_ROOT/environment/mac/.bash_profile
cd \$REPO_ROOT" > ~/.bash_profile

# configure git
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Install nvm - periodically check to see if the version below is the latest
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.1/install.sh | bash
nvm install lts/*
npm i -g npm
npm i -g npm-check-updates create-react-native-app flow-typed yarn
nvm install node
nvm reinstall-packages lts/*
# nvm alias default node

# Install Skype
curl -JL https://get.skype.com/go/getskype-macosx -o ~/Downloads/InstallSkype.dmg
hdiutil attach ~/Downloads/InstallSkype.dmg
sudo ditto /Volumes/Skype/Skype.app /Applications/Skype.app
diskutil unmount Skype
rm ~/Downloads/InstallSkype.dmg
# mute Skype sounds except messages and calls
# disable the auto spelling correction because technical acronyms and names get so often mis-corrected
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
# change energy saver settings to not be so aggressive
# Restart your computer

# Install Android Studio
curl -JL https://dl.google.com/dl/android/studio/install/2.3.1.0/android-studio-ide-162.3871768-mac.dmg -o ~/Downloads/InstallAndroidStudio.dmg
hdiutil attach ~/Downloads/InstallAndroidStudio.dmg
sudo ditto /Volumes/Android\ Studio\ 2.3.1/Android\ Studio.app /Applications/Android\ Studio.app
diskutil unmount Android\ Studio\ 2.3.1
rm ~/Downloads/InstallAndroidStudio.dmg
# Install the NDK from Android Studio
# Install JDK 8
open http://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html

# Install CoRD

# Install Sketch

# Install SourceTree

# Install Visual Studio Code

# Install XMind
curl -JL http://dl2.xmind.net/xmind-downloads/xmind-8-update1-macosx.dmg -o ~/Downloads/InstallXMind.dmg
hdiutil attach ~/Downloads/InstallXMind.dmg
sudo ditto /Volumes/XMind/XMind.app /Applications/XMind.app
diskutil unmount XMind
rm ~/Downloads/InstallXMind.dmg

# Install ControlPlane
curl -JL https://www.dropbox.com/s/lhuyzp1csx3f9cc/ControlPlane-1.6.6.dmg?dl=1 -o ~/Downloads/InstallControlPlane.dmg
hdiutil attach ~/Downloads/InstallControlPlane.dmg
sudo ditto /Volumes/ControlPlane/ControlPlane.app /Applications/ControlPlane.app
diskutil unmount ControlPlane
rm ~/Downloads/InstallControlPlane.dmg
open /Applications/ControlPlane.app
# Disable auto-correct
# Install BeyondCompare
# https://www.scootersoftware.com/BCompareOSX-4.2.0.22108.zip
# Install Charles
# Install Framer
# Show Volume in the menu bar
defaults write com.apple.systemuiserver menuExtras -array-add "/System/Library/CoreServices/Menu Extras/Volume.menu"
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.volume" -bool true
# Increase window resize speed for Cocoa applications
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
# Save to disk (not to iCloud) by default
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
# Automatically quit printer app once the print jobs complete
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
# Disable the "Are you sure you want to open this application?" dialog
defaults write com.apple.LaunchServices LSQuarantine -bool false
# Display ASCII control characters using caret notation in standard text views
defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true
# Disable Resume system-wide
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
# Disable automatic termination of inactive apps
defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true
# Disable the crash reporter
defaults write com.apple.CrashReporter DialogType -string "none"
# Set Help Viewer windows to non-floating mode
defaults write com.apple.helpviewer DevMode -bool true
# Reveal IP address, hostname, OS version, etc. when clicking the clock in the login window
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
# Check for software updates daily, not just once per week
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

# Mouse Behavior
# Trackpad: enable tap to click for this user and for the login screen
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
# Trackpad: map bottom right corner to right-click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true
# Trackpad: swipe between pages with three fingers
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true
defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 1
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 1
# Disable "natural" (Lion-style) scrolling
# defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
# Increase sound quality for Bluetooth headphones/headsets
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40
# Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
# Use scroll gesture with the Ctrl (^) modifier key to zoom
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
# Follow the keyboard focus while zoomed in
defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
# Disable press-and-hold for keys in favor of key repeat
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Automatically illuminate built-in MacBook keyboard in low light
defaults write com.apple.BezelServices kDim -bool true
# Turn off keyboard illumination when computer is not used for 5 minutes
defaults write com.apple.BezelServices kDimTime -int 300
# Set language and text formats
defaults write NSGlobalDomain AppleLanguages -array "en"
defaults write NSGlobalDomain AppleLocale -string "en_US@currency=USD"
defaults write NSGlobalDomain AppleMeasurementUnits -string "Inches"
defaults write NSGlobalDomain AppleMetricUnits -bool false
# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Screen
# Require password immediately after sleep or screen saver begins
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
# Save screenshots to the desktop
defaults write com.apple.screencapture location -string "$HOME/Desktop"
# Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
defaults write com.apple.screencapture type -string "png"
# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true
# Enable subpixel font rendering on non-Apple LCDs
defaults write NSGlobalDomain AppleFontSmoothing -int 2
# Enable HiDPI display modes (requires restart)
sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

# Finder
# Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons
defaults write com.apple.finder QuitMenuItem -bool true
# Finder: disable window animations and Get Info animations
defaults write com.apple.finder DisableAllAnimations -bool true
# Show icons for hard drives, servers, and removable media on the desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
# Finder: show hidden files by default
defaults write com.apple.finder AppleShowAllFiles -bool true
# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# Finder: show status bar
defaults write com.apple.finder ShowStatusBar -bool true
# Finder: allow text selection in Quick Look
defaults write com.apple.finder QLEnableTextSelection -bool true
# Display full POSIX path as Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
# When performing a search, search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
# Avoid creating .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
# Disable disk image verification
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
# Automatically open a new Finder window when a volume is mounted
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
# Use list view in all Finder windows by default
# You can set the other view modes by using one of these four-letter codes: icnv, clmv, Flwv
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
# Disable the warning before emptying the Trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false
# Empty Trash securely by default
defaults write com.apple.finder EmptyTrashSecurely -bool true
# Enable AirDrop over Ethernet and on unsupported Macs running Lion
defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

# Dock & hot corners
# Enable highlight hover effect for the grid view of a stack (Dock)
defaults write com.apple.dock mouse-over-hilte-stack -bool true
# Set the icon size of Dock items to 36 pixels
defaults write com.apple.dock tilesize -int 36
# Enable spring loading for all Dock items
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
# Show indicator lights for open applications in the Dock
defaults write com.apple.dock show-process-indicators -bool true
# Don’t animate opening applications from the Dock
defaults write com.apple.dock launchanim -bool false
# Speed up Mission Control animations
defaults write com.apple.dock expose-animation-duration -float 0.1
# Remove the auto-hiding Dock delay
defaults write com.apple.Dock autohide-delay -float 0
# Remove the animation when hiding/showing the Dock
defaults write com.apple.dock autohide-time-modifier -float 0
# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool true
# Make Dock icons of hidden applications translucent
defaults write com.apple.dock showhidden -bool true

# Hot corners
# Top right screen corner → Start screen saver
defaults write com.apple.dock wvous-tr-corner -int 5
defaults write com.apple.dock wvous-tr-modifier -int 0

# Safari & WebKit
# Set Safari’s home page to about:blank for faster loading
defaults write com.apple.Safari HomePage -string "about:blank"
# Prevent Safari from opening ‘safe’ files automatically after downloading
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
# Hide Safari’s bookmarks bar by default
defaults write com.apple.Safari ShowFavoritesBar -bool false
# Disable Safari’s thumbnail cache for History and Top Sites
defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
# Enable Safari’s debug menu
defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
# Make Safari’s search banners default to Contains instead of Starts With
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
# Remove useless icons from Safari’s bookmarks bar
defaults write com.apple.Safari ProxiesInBookmarksBar "()"
# Enable the Develop menu and the Web Inspector in Safari
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
# Add a context menu item for showing the Web Inspector in web views
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
# Enable the WebKit Developer Tools in the Mac App Store
defaults write com.apple.appstore WebKitDeveloperExtras -bool true

# iTunes
# Disable the iTunes store link arrows
defaults write com.apple.iTunes show-store-link-arrows -bool false
# Disable the Genius sidebar in iTunes
defaults write com.apple.iTunes disableGeniusSidebar -bool true
# Disable the Ping sidebar in iTunes
defaults write com.apple.iTunes disablePingSidebar -bool true
# Disable all the other Ping stuff in iTunes
defaults write com.apple.iTunes disablePing -bool true
# Disable radio stations in iTunes
defaults write com.apple.iTunes disableRadio -bool true
# Make ⌘ + F focus the search input in iTunes
defaults write com.apple.iTunes NSUserKeyEquivalents -dict-add "Target Search Field" "@F"

# Mail
# Disable send and reply animations in Mail.app
defaults write com.apple.mail DisableReplyAnimations -bool true
defaults write com.apple.mail DisableSendAnimations -bool true
# Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app
defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@U21a9"

# Terminal
# Enable "focus follows mouse" for Terminal.app and all X11 apps i.e. hover over a window and start typing in it without clicking first
defaults write com.apple.terminal FocusFollowsMouse -bool true
defaults write org.x.X11 wm_ffm -bool true

# Time Machine
# Prevent Time Machine from prompting to use new hard drives as backup volume
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# Address Book, Dashboard, iCal, TextEdit, and Disk Utility
# Enable the debug menu in Address Book
defaults write com.apple.addressbook ABShowDebugMenu -bool true
# Enable Dashboard dev mode (allows keeping widgets on the desktop)
defaults write com.apple.dashboard devmode -bool true
# Use plain text mode for new TextEdit documents
defaults write com.apple.TextEdit RichText -int 0
# Open and save files as UTF–8 in TextEdit
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
# Enable the debug menu in Disk Utility
defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
defaults write com.apple.DiskUtility advanced-image-options -bool true

# Quick Look Generators
# iOS Provisioning Profile Quick Look Generator
curl -JL "https://github.com/chockenberry/Provisioning/releases/download/1.0.4/Provisioning-1.0.4.zip" -o ~/Downloads/qlprovisioning.zip
unzip -q ~/Downloads/qlprovisioning.zip
sudo mv ~/Downloads/qlprovisioning/Provisioning.qlgenerator /Library/QuickLook

fi
