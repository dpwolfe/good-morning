#!/usr/bin/env bash

# Do not exit immediately if a command exits with a non-zero status.
set +o errexit
# Print commands and their arguments as they are executed.
# Turn on for debugging
# set -o xtrace

function randstring32 {
  env LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1
}

passphrase=randstring32
function encryptToFile {
  echo "$1" | openssl enc -aes-256-cbc -k $passphrase > "$2"
}

function decryptFromFile {
  openssl enc -aes-256-cbc -d -k $passphrase < "$1"
}

function askto {
  echo "Do you want to $1? $3"
  read -r -n 1 -p "(Y/n) " yn < /dev/tty;
  echo # echo newline after input
  case $yn in
    y|Y ) ${2}; return 0;;
    n|N ) return 1;;
  esac
}

function prompt {
  if [ -n "$2" ]; then
    read -r -p "$1" "$2" < /dev/tty
  else
    read -r -p "$1" < /dev/tty
  fi
}

function promptsecret {
  read -r -s -p "$1: " "$2" < /dev/tty
  echo # echo newline after input
}

if [ -e "$passfile" ]; then
  rm "$passfile"
fi
unset passfile
function sudoit {
  if [ -z "$passfile" ]; then
    passfile="$HOME/.temp_$(randstring32)"
    local p=
    while [ -z "$p" ] || ! echo "$p" | sudo -S -p "" printf ""; do
      promptsecret "Password" p
    done
    encryptToFile "$p" "$passfile"
  fi
  decryptFromFile "$passfile" | sudo -S -p "" "$@"
}

function masinstall {
  if ! mas list | grep "$1" > /dev/null; then
    # macOS Sierra issue for users who have never installed the given app - https://github.com/mas-cli/mas/issues/85
    mas install "$1" || \
      open "https://itunes.apple.com/us/app/id$1" && \
      echo "GitHub issue: https://github.com/mas-cli/mas/issues/85" && \
      prompt "Install $2 from the Mac App Store and hit Enter when finished..."
  fi
}

function dmginstall {
  local appPath="/Applications/$1.app"
  local appPathUser="$HOME/Applications/$1.app"
  local downloadPath="$HOME/Downloads/$1.dmg"
  # only offer to install if not installed in either the user or "all users" locations
  if ! [ -d "$appPath" ] && ! [ -d "$appPathUser" ] && askto "install $1"; then
    curl -JL "$2" -o "$downloadPath"
    yes | hdiutil attach "$downloadPath" > /dev/null
    # install in the "all users" location
    sudoit ditto "/Volumes/$3/$1.app" "$appPath"
    diskutil unmount "$3" > /dev/null
    rm "$downloadPath"
  fi
}

if ! type xcversion &> /dev/null; then
  echo "Installing xcode-install for managing Xcode..."
  # https://github.com/KrauseFx/xcode-install
  # The alternative install instructions must be used since there is not a working
  # compiler on the system at this point in the setup.
  curl -sL https://github.com/neonichu/ruby-domain_name/releases/download/v0.5.99999999/domain_name-0.5.99999999.gem -o ~/Downloads/domain_name-0.5.99999999.gem
  sudoit gem install ~/Downloads/domain_name-0.5.99999999.gem < /dev/tty
  sudoit gem install --conservative xcode-install < /dev/tty
  rm -f ~/Downloads/domain_name-0.5.99999999.gem
fi

xcode_version=9
if ! /usr/bin/xcode-select -p &> /dev/null; then
  echo "Installing Xcode $xcode_version..."
  xcversion update < /dev/tty
  xcversion install $xcode_version < /dev/tty
  echo "Installing Xcode command line tools..."
  xcversion install-cli-tools < /dev/tty
elif ! xcversion selected 2>&1 | grep $xcode_version > /dev/null; then
  echo "Installing Xcode $xcode_version..."
  xcversion install $xcode_version < /dev/tty
  xcversion install-cli-tools < /dev/tty
fi
unset xcode_version

if /usr/bin/xcrun clang 2>&1 | grep license > /dev/null; then
  echo "Accepting the Xcode license..."
  sudoit xcodebuild -license accept
  echo "Installing Xcode packages..."
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDevice.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDeviceDevelopment.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
fi

GITHUB_EMAIL="$(git config --global --get user.email)"
unset gitHubEmailChanged
if [ -z "$GITHUB_EMAIL" ]; then
  prompt "Enter your GitHub email address: " GITHUB_EMAIL
  git config --global user.email "$GITHUB_EMAIL"
  gitHubEmailChanged=1
fi
GITHUB_NAME="$(git config --global --get user.name)"
unset gitHubNameChanged
if [ -z "$GITHUB_NAME" ]; then
  prompt "Enter your full name used on GitHub: " GITHUB_NAME
  git config --global user.name "$GITHUB_NAME"
  gitHubNameChanged=1
fi
# Generate a new SSH key for GitHub https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/
GITHUB_KEYS_URL="https://github.com/settings/keys"
if [ -n "$gitHubEmailChanged" ] && askto "create a GitHub SSH key for $GITHUB_EMAIL"; then
  ssh-keygen -t rsa -b 4096 -C "$GITHUB_EMAIL" < /dev/tty
  # start ssh-agent
  eval "$(ssh-agent -s)"
  # automatically load the keys and store passphrases in your keychain
  echo "Host *
 AddKeysToAgent yes
 UseKeychain yes
 IdentityFile \"$HOME/.ssh/id_rsa\"" > "$HOME/.ssh/config"
  # add your ssh key to ssh-agent
  ssh-add -K "$HOME/.ssh/id_rsa"
  # copy public ssh key to clipboard for pasting on GitHub
  pbcopy < "$HOME/.ssh/id_rsa.pub"
  echo "SSH key copied to clipboard. GitHub will be opened next."
  echo "Click 'New SSH key' on GitHub when it opens and paste in the copied key."
  prompt "Hit Enter to open up GitHub... ($GITHUB_KEYS_URL)"
  open "$GITHUB_KEYS_URL"
  prompt "Hit Enter after the SSH key is saved on GitHub..."
fi

if ! [ -d "/Applications/GPG Keychain.app" ]; then
  dmg="$HOME/Downloads/GPGSuite.dmg"
  curl -JL https://releases.gpgtools.org/GPG_Suite-2017.1b3-v2.dmg -o "$dmg"
  hdiutil attach "$dmg"
  sudoit installer -pkg "/Volumes/GPG Suite/Install.pkg" -target /
  diskutil unmount "GPG Suite"
  rm "$dmg"
fi

if ! [ -s "$HOME/.rvm/scripts/rvm" ] && ! type rvm &> /dev/null; then
  echo "Installing RVM..."
  gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  curl -sSL https://get.rvm.io | bash -s stable
  # shellcheck source=/dev/null
  source "$HOME/.rvm/scripts/rvm"
  rvm install ruby --default
  rvm cleanup all
else
  CURRENT_RUBY_VERSION="$(ruby --version | sed -E 's/ ([0-9.]+).*/-\1/')"
  LATEST_RUBY_VERSION="$(rvm list known | grep "\[ruby-" | tail -1 | tr -d '[]')"
  if [[ "$CURRENT_RUBY_VERSION" != "$LATEST_RUBY_VERSION" ]]; then
    echo "Upgrading RVM..."
    rvm get stable --auto
    echo "Upgrading Ruby from $CURRENT_RUBY_VERSION to $LATEST_RUBY_VERSION..."
    rvm upgrade "$CURRENT_RUBY_VERSION" "$LATEST_RUBY_VERSION"
    rvm create alias default ruby
    rvm cleanup all
  fi
  unset CURRENT_RUBY_VERSION
  unset LATEST_RUBY_VERSION
fi

rvm use system &> /dev/null
echo "Checking system ruby gem versions..."
if [ "$(gem outdated)" ]; then
  echo "Updating system ruby gems..."
  sudoit gem update
fi
rvm default &> /dev/null
echo "Checking rvm ruby gem versions..."
if [ "$(gem outdated)" ]; then
  echo "Updating ruby gems..."
  gem update
fi
if ! gem list --local | grep xcode-install &> /dev/null; then
  echo "Replacing xcode-install gem that was installed using a work-around..."
  gem install xcode-install
fi

if ( [ -n "$gitHubEmailChanged" ] || [ -n "$gitHubNameChanged" ] ) && askto "create a Git GPG signing key for $GITHUB_EMAIL"; then
  promptsecret "Enter the passphrase to use for the GPG key" GPG_PASSPHRASE
  gpg --batch --gen-key <<EOF
%echo "Generating a GPG key for signing Git operations...""
%echo "Learn why here: https://git-scm.com/book/tr/v2/Git-Tools-Signing-Your-Work"
%echo "Learn about GitHub's use here: https://help.github.com/articles/generating-a-new-gpg-key/"
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GITHUB_NAME
Name-Comment: Git signing key
Name-Email: $GITHUB_EMAIL
Expire-Date: 2y
Passphrase: $GPG_PASSPHRASE
%commit
%echo Signing key created.
EOF
  unset GPG_PASSPHRASE
  todaysdate=$(date +"%Y-%m-%d")
  expr="^sec   4096R\/([[:xdigit:]]{16}) $todaysdate.*"
  key=$(gpg --list-secret-keys --keyid-format LONG | grep -E "$expr" | sed -E "s/$expr/\1/")
  # copy the GPG public key for GitHub
  gpg --armor --export "$key" | pbcopy
  echo "GPG key copied to clipboard. GitHub will be opened next."
  echo "Click 'New GPG key' on GitHub when it opens and paste in the copied key."
  prompt "Hit Enter to open up GitHub... ($GITHUB_KEYS_URL)"
  open "$GITHUB_KEYS_URL"
  prompt "Hit Enter after the GPG key is saved on GitHub to continue..."
  # enable autos-signing of all the commits
  git config --global commit.gpgsign true
  # Silence output about needing a passphrase on each commit
  # echo 'no-tty' >> "$HOME/.gnupg/gpg.conf"
fi

# Pick a default repo root unless one is already set
if [ -z "${REPO_ROOT+x}" ]; then
  REPO_ROOT="$HOME/repo"
fi
# Create local repository root
if ! [ -d "$REPO_ROOT" ]; then
  echo "Creating $REPO_ROOT"
  mkdir -p "$REPO_ROOT"
fi
# Setup clone of environment repository
ENVIRONMENT_REPO_ROOT="$REPO_ROOT/environment"
if ! [ -d "$ENVIRONMENT_REPO_ROOT" ]; then
  echo "Cloning environment repository..."
  git clone https://github.com/dpwolfe/environment.git "$ENVIRONMENT_REPO_ROOT"
  echo "export REPO_ROOT=\"\$HOME/repo\"
source \"\$REPO_ROOT/environment/mac/.bash_profile\"
cd \"\$REPO_ROOT\"" >> "$HOME/.bash_profile"

  # copy some starter shell environment files
  cp "$ENVIRONMENT_REPO_ROOT/mac/.inputrc" "$HOME/.inputrc"
  cp "$ENVIRONMENT_REPO_ROOT/mac/.vimrc" "$HOME/.vimrc"
  cp -rf "$ENVIRONMENT_REPO_ROOT/mac/.vim" "$HOME/.vim"
  # set flag to indicate this is the first run to turn on additional setup features
  FIRST_RUN=1
fi

# Install homebrew - https://brew.sh
if ! type "brew" &> /dev/null; then
  yes '' | /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
  echo "Updating Homebrew..."
  brew update
  echo "Checking for outdated Homebrew formulas..."
  if [ "$(brew upgrade)" != "" ]; then
    echo "Cleaning up Homebrew formula cache..."
    brew cleanup # works better than adding --cleanup
    # If there was any output from the cleanup task, assume a formula changed or was installed.
    # Homebrew Doctor can take a long time to run, so now running only after formula changes...
    echo "Running Hombrew Doctor..."
    brew doctor
  fi
  echo "Checking for outdated Homebrew Casks..."
  for outdatedCask in $(brew cask outdated | sed -E 's/^([^ ]*) .*$/\1/'); do
    echo "Upgrading $outdatedCask..."
    brew cask reinstall "$outdatedCask"
    BREW_CASK_UPGRADES=1
  done
fi
# Having Homebrew issues? Run this command below.
# cd /usr/local && sudoit chown -R "$(whoami)" bin etc include lib sbin share var Frameworks

# Install cask brews
caskBrews=(
  android-studio
  atom
  beyond-compare
  blue-jeans-browser-plugin
  blue-jeans-launcher
  charles
  controlplane
  cord
  dropbox
  framer
  google-backup-and-sync
  google-chrome
  handbrake
  iterm2
  java
  keeweb
  keyboard-maestro
  microsoft-office
  obs
  omnifocus
  omnigraffle
  onedrive
  provisionql
  qladdict
  qlcolorcode
  qlmarkdown
  sketch
  skype
  slack
  sourcetree
  spotify
  the-unarchiver
  virtualbox
  visual-studio-code
  wavtap
  xmind
  zeplin
  zoomus
)
brew tap caskroom/cask
brewtempfile="$HOME/brewlist.temp"
brew cask list > "$brewtempfile"
for caskBrew in "${caskBrews[@]}";
do
  if ! grep "$caskBrew" "$brewtempfile" > /dev/null; then
    brew cask install "$caskBrew"
    NEW_BREW_CASK_INSTALLS=1
  fi
done

if [ -n "$NEW_BREW_CASK_INSTALLS" ] || [ -n "$BREW_CASK_UPGRADES" ]; then
  unset BREW_CASK_UPGRADES;
  echo "Cleaning up Homebrew Cask cache..."
  brew cask cleanup
fi

# Install brews
# shellcheck disable=SC2034
brews=(
  bash-completion
  certbot # For generating SSL certs with Let's Encrypt
  docker
  go
  git
  jq
  kubernetes-cli
  mas # Mac App Store command line interface - https://github.com/mas-cli/mas
  maven
  python
  python3
  shellcheck # shell script linting
  terraform
  terragrunt
  transcrypt
  vim
  wget
  yarn
  yubico-piv-tool
)
brew list > "$brewtempfile"
for brew in "${brews[@]}";
do
  if ! grep "$brew" "$brewtempfile" > /dev/null; then
    brew install "$brew"
  fi
done
rm "$brewtempfile"

function pickbin {
  local versions="$1"
  for version in $versions; do
    if type $version &> /dev/null; then
      echo "$version"
      return
    fi
  done
}

function findpip {
  echo "$(pickbin 'pip pip2 pip2.7 pip3 pip3.6')"
}

function pipinstall {
  $(findpip) install "$1"
}

if ! type "pip-review" &> /dev/null; then
  pipinstall pip-review
fi

# Install Node Version Manager
NVM_VERSION="0.33.5"
# if nvm is already installed, load it in order to check its version
if ! [ -s "$HOME/.nvm/nvm.sh" ] || ! nvm --version | grep "$NVM_VERSION" > /dev/null; then
  # https://github.com/creationix/nvm#install-script
  echo "Installing Node Version Manager v$NVM_VERSION"
  # run the install script
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v$NVM_VERSION/install.sh | bash
fi

echo "Loading Node Version Manager..."
# shellcheck source=/dev/null
. "$HOME/.nvm/nvm.sh" > /dev/null

function upgradenode {
  local installed_version="$1"
  local latest_version="$2"
  local active_version
  active_version="$(node -v)"
  # Install highest Long Term Support build as a recommended "prod" node version
  if [[ "$installed_version" != "$latest_version" ]]; then
    echo "Installing Node.js $latest_version..."
    nvm install --lts
    local old_version=$installed_version # rename for readability
    if [[ "$active_version" == "$old_version" ]]; then
      # just uninstalled the version that was active, so track the new one as the active_version
      active_version=$latest_version
    fi
    if [[ "$old_version" != "N/A" ]]; then
      echo "Installing Node.js packages from $old_version to $latest_version..."
      nvm reinstall-packages "$old_version"
      echo "Uninstalling Node.js $old_version..."
      nvm uninstall "$old_version"
    fi
    # Upgrade npm
    npm i -g npm
    # Install some staples used with great frequency
    npm i -g npm-check-updates
    # Install avn, avn-nvm and avn-n to enable automatic 'nvm use' when a .nvmrc is present
    npm i -g avn avn-nvm avn-n
  else
    echo "Checking Node.js $installed_version global npm package versions..."
    nvm use "$installed_version" > /dev/null
    npm update -g
  fi
  # Switch back to previously active node version in case it changed.
  nvm use "$active_version" > /dev/null
}

echo "Checking version of installed Node.js..."
upgradenode "$(nvm version node)" "$(nvm version-remote node)"
echo "Checking version of installed Node.js LTS..."
upgradenode "$(nvm version lts/*)" "$(nvm version-remote --lts)"

if ! pip-review | grep "Everything up-to-date" > /dev/null; then
  echo "Upgrading pip installed packages..."
  # ensure password for sudo is ready since we want to custom pass it using the -H flag
  sudoit printf ""
  # call pip-review with python -m to enable updating pip-review itself
  # shellcheck disable=SC2002
  decryptFromFile "$passfile" | sudo -H -S -p "" pip-review --auto
fi

if ! $(findpip) freeze | grep "awscli=" > /dev/null; then
  echo "Installing AWS CLI..."
  # ensure password for sudo is ready since we want to custom pass it using the -H flag
  sudoit printf ""
  # passing -H to avoid warnings instead of using sudoit
  # shellcheck disable=SC2002
  decryptFromFile "$passfile" | sudo -H -S -p "" "$(findpip)" install awscli
fi

if [ -n "$FIRST_RUN" ] && askto "review and install some recommended applications"; then
  # Install Fixed Solarized iTerm colors https://github.com/yuex/solarized-dark-iterm2
  curl -JL "https://github.com/yuex/solarized-dark-iterm2/raw/master/Solarized%20Dark%20(Fixed).itermcolors" -o "$HOME/Downloads/SolarizedFixed.itermcolors"
  echo "Follow these steps to complete the iTerm setup:"
  echo "1. Import the Solarized Dark (Fixed) iTerm colors into Preferences > Profiles > Colors > Color Presets... > Import"
  echo "2. Select that imported preset that is now in the drop down list."
  echo "3. Set the iTerm buffer scroll back to unlimited in Settings > Profiles > Terminal"
  echo "4. Install the iTerm shell integrations from the File menu"
  echo "5. Use iTerm instead of Terminal from now on."
  prompt "Hit Enter to continue..."
  # todo: insert directly into plist located here $HOME/Library/Preferences/com.googlecode.iterm2.plist
  # todo: change plist directly for scroll back Root > New Bookmarks > Item 0 > Unlimited Scrollback > Boolean YES

  # Ensure Atom Shell Commands are installed
  if [ -d "/Applications/Atom.app" ] && ! type "apm" > /dev/null; then
    echo "You need to install the Atom shell commands from inside Atom."
    echo "After Atom opens, go to the Atom menu and select Atom > Install Shell Commands."
    prompt "Hit Enter to open Atom..."
    open "/Applications/Atom.app"
    prompt "Select the menu item Atom > Install Shell Commands and hit Enter here when finished..."
    if ! apm list | grep "── vim-mode@" > /dev/null && askto "install Atom vim-mode"; then
      apm install vim-mode ex-mode
    fi
  fi
fi

if [ -n "$FIRST_RUN" ] && ! (defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall && \
  defaults read /Library/Preferences/com.apple.commerce AutoUpdate && \
  defaults read /Library/Preferences/com.apple.commerce AutoUpdateRestartRequired) &> /dev/null && \
  askto "enable auto download & install of Mac App Store updates and macOS updates"; then
    sudoit defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
    sudoit defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
    sudoit defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
    sudoit defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
    sudoit defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true
    sudoit defaults write /Library/Preferences/com.apple.commerce AutoUpdateRestartRequired -bool true
fi

# Install atom packages
apms=(
  atom-typescript
  busy-signal
  circle-ci
  docblockr
  file-icons
  git-plus
  git-time-machine
  highlight-selected
  intentions
  jumpy
  language-docker
  language-terraform # this caused freezes for me, uninstall and reinstall if that happens
  last-cursor-position
  linter
  linter-docker
  linter-eslint
  # todo: auto add -x option to shellcheck settings in atom
  linter-shellcheck
  linter-ui-default
  merge-conflicts
  nuclide
  prettier-atom
  project-manager
  set-syntax
  sort-lines
  split-diff
)
if type "apm" > /dev/null; then
  echo "Checking installed Atom package versions..."
  # Update all the Atom packages
  yes | apm upgrade --no-confirm
  # Get list of currently installed packages
  apmtempfile="$HOME/apmlist.temp"
  apm list > "$apmtempfile"
  for pkg in "${apms[@]}";
  do
    if ! grep "── $pkg@" "$apmtempfile" > /dev/null; then
      apm install "$pkg"
    fi
  done
  rm "$apmtempfile"
fi
# Disable language-terraform by default since it will cause Atom to lock up after
# a couple uses. Re-enable it manually as needed.
apm disable language-terraform &> /dev/null

if [ -n "$NEW_BREW_CASK_INSTALLS" ]; then
  unset NEW_BREW_CASK_INSTALLS
  # Moved this lower since it's not important to do this earlier in the script
  # and it might avoid prompting for the password until more of the work is done.
  echo "Triggering re-index of Spotlight search for benefit of new brew casks..."
  sudoit mdutil -a -i off
  sudoit mdutil -a -i on
fi

if [ -n "$FIRST_RUN" ] && askto "set some opinionated starter system settings"; then
  echo "Modifying System Settings"
  echo "Only show icons of running apps in app bar, using Spotlight to launch"
  defaults write com.apple.dock static-only -bool true
  echo "Auto show and hide the menu bar"
  defaults write -g _HIHideMenuBar -bool false
  echo "Attach the dock to the left side, the definitive optimal location according to the community"
  defaults write com.apple.dock orientation left
  echo "Enable tap to click on trackpad"
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  echo "Bump up the trackpad speed a couple notches"
  defaults write -g com.apple.trackpad.scaling 2
  echo "Turn off the annoying auto-capitalize while typing"
  defaults write -g NSAutomaticCapitalizationEnabled -bool false
  echo "Set beep volume to 0"
  defaults write -g com.apple.sound.beep.volume -int 0
  echo "Turn off the cursor location assist that will grow the cursor size when shaken"
  defaults write -g CGDisableCursorLocationMagnification -bool true
  echo "Bump the mouse scaling up a couple notches"
  defaults write -g com.apple.mouse.scaling -float 2
  echo "Set interface style to dark"
  defaults write -g AppleInterfaceStyle -string "Dark"
  echo "Set a short alert sound"
  defaults write -g com.apple.sound.beep.sound -string "/System/Library/Sounds/Pop.aiff"
  # todo: hide siri
  echo "Set fast speed key repeat rate, setting to 0 basically deletes everything at"
  echo "once in some slower apps. 1 is still too fast for some apps. 2 is the"
  echo "reasonable safe min."
  defaults write -g KeyRepeat -int 2
  echo "Set the delay until repeat to be very short"
  defaults write -g InitialKeyRepeat -int 15
  echo "Disable the auto spelling correction since technical acronyms and names get so often miss-corrected"
  defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
  echo "Show Volume in the menu bar"
  defaults write com.apple.systemuiserver menuExtras -array-add "/System/Library/CoreServices/Menu Extras/Volume.menu"
  defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.volume" -bool true
  echo "Increase window resize speed for Cocoa applications"
  defaults write -g NSWindowResizeTime -float 0.001
  echo "Expand save panel by default"
  defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
  echo "Expand print panel by default"
  defaults write -g PMPrintingExpandedStateForPrint -bool true
  echo "Save to disk (not to iCloud) by default"
  defaults write -g NSDocumentSaveNewDocumentsToCloud -bool false
  echo "Automatically quit printer app once the print jobs complete"
  defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
  echo "Disable the "Are you sure you want to open this application?" dialog"
  defaults write com.apple.LaunchServices LSQuarantine -bool false
  echo "Display ASCII control characters using caret notation in standard text views"
  defaults write -g NSTextShowsControlCharacters -bool true
  echo "Disable Resume system-wide"
  defaults write -g NSQuitAlwaysKeepsWindows -bool false
  echo "Disable automatic termination of inactive apps"
  defaults write -g NSDisableAutomaticTermination -bool true
  echo "Disable automatic period substitution as it’s annoying when typing code"
  defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
  echo "Disable the crash reporter"
  defaults write com.apple.CrashReporter DialogType -string "none"
  echo "Set Help Viewer windows to non-floating mode"
  defaults write com.apple.helpviewer DevMode -bool true
  echo "Reveal IP address, hostname, OS version, etc. when clicking the clock in the login window"
  sudoit defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
  echo "Check for software updates daily, not just once per week"
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

  echo "Modifying Mouse Settings"
  echo "Trackpad: enable tap to click for this user and for the login screen"
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.mouse.tapBehavior -int 1
  echo "Trackpad: map bottom right corner to right-click"
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
  defaults -currentHost write -g com.apple.trackpad.trackpadCornerClickBehavior -int 1
  defaults -currentHost write -g com.apple.trackpad.enableSecondaryClick -bool true
  echo "Trackpad: swipe between pages with three fingers"
  defaults write -g AppleEnableSwipeNavigateWithScrolls -bool true
  defaults -currentHost write -g com.apple.trackpad.threeFingerHorizSwipeGesture -int 1
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 1
  echo "Increase sound quality for Bluetooth headphones/headsets"
  defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40
  echo "Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)"
  defaults write -g AppleKeyboardUIMode -int 3
  echo "Use scroll gesture with the Ctrl (^) modifier key to zoom"
  defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
  defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
  echo "Follow the keyboard focus while zoomed in"
  defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
  echo "Disable press-and-hold for keys in favor of key repeat"
  defaults write -g ApplePressAndHoldEnabled -bool false
  echo "Automatically illuminate built-in MacBook keyboard in low light"
  defaults write com.apple.BezelServices kDim -bool true
  echo "Turn off keyboard illumination when computer is not used for 5 minutes"
  defaults write com.apple.BezelServices kDimTime -int 300
  echo "Set language and text formats"
  defaults write -g AppleLanguages -array "en"
  defaults write -g AppleLocale -string "en_US@currency=USD"
  defaults write -g AppleMeasurementUnits -string "Inches"
  defaults write -g AppleMetricUnits -bool false
  echo "Disable auto-correct"
  defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false

  echo "Modifying Screen Settings"
  echo "Require password immediately after sleep or screen saver begins"
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
  echo "Top right screen corner starts the screen saver instead of using idle time"
  defaults write com.apple.dock wvous-tr-corner -int 5
  defaults write com.apple.dock wvous-tr-modifier -int 0
  defaults -currentHost write com.apple.screensaver idleTime 0
  echo "Save screenshots to the desktop"
  defaults write com.apple.screencapture location -string "$HOME/Desktop"
  echo "Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)"
  defaults write com.apple.screencapture type -string "png"
  echo "Disable shadow in screenshots"
  defaults write com.apple.screencapture disable-shadow -bool true
  echo "Enable subpixel font rendering on non-Apple LCDs"
  defaults write -g AppleFontSmoothing -int 2
  echo "Enable HiDPI display modes (requires restart)"
  sudoit defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  echo "Modifying Finder Settings"
  echo "Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons"
  defaults write com.apple.finder QuitMenuItem -bool true
  echo "Finder: disable window animations and Get Info animations"
  defaults write com.apple.finder DisableAllAnimations -bool true
  echo "Show icons for hard drives, servers, and removable media on the desktop"
  defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
  defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
  echo "Finder: show hidden files by default"
  defaults write com.apple.finder AppleShowAllFiles -bool true
  echo "Finder: show all filename extensions"
  defaults write -g AppleShowAllExtensions -bool true
  echo "Finder: show status bar"
  defaults write com.apple.finder ShowStatusBar -bool true
  echo "Finder: allow text selection in Quick Look"
  defaults write com.apple.finder QLEnableTextSelection -bool true
  echo "Display full POSIX path as Finder window title"
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  echo "When performing a search, search the current folder by default"
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  echo "Disable the warning when changing a file extension"
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  echo "Avoid creating .DS_Store files on network volumes"
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  echo "Disable disk image verification"
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
  echo "Automatically open a new Finder window when a volume is mounted"
  defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  echo "Use list view in all Finder windows by default"
  # You can set the other view modes by using one of these four-letter codes: icnv, clmv, Flwv
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  echo "Disable the warning before emptying the Trash"
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
  echo "Empty Trash securely by default"
  defaults write com.apple.finder EmptyTrashSecurely -bool true
  echo "Enable AirDrop over Ethernet and on unsupported Macs running Lion"
  defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true
  echo "Display all file sizes in Finder windows"
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Delete "StandardViewSettings:ExtendedListViewSettings:calculateAllSizes" bool'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Add "StandardViewSettings:ExtendedListViewSettings:calculateAllSizes" bool true'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Delete "StandardViewSettings:ListViewSettings:calculateAllSizes" bool'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Add "StandardViewSettings:ListViewSettings:calculateAllSizes" bool true'
  echo "Turn off Finder sounds"
  defaults write com.apple.finder 'FinderSounds' -bool false
  echo "Making ~/Library visible"
  /usr/bin/chflags nohidden "$HOME/Library"
  echo "Disabling '<App> is an application downloaded from the internet. Are you sure you want to open it?"
  defaults write com.apple.LaunchServices LSQuarantine -bool false

  echo "Modifying Dock Settings"
  echo "Enable highlight hover effect for the grid view of a stack (Dock)"
  defaults write com.apple.dock mouse-over-hilte-stack -bool true
  echo "Set the icon size of Dock items to 36 pixels"
  defaults write com.apple.dock tilesize -int 36
  echo "Enable spring loading for all Dock items"
  defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
  echo "Show indicator lights for open applications in the Dock"
  defaults write com.apple.dock show-process-indicators -bool true
  echo "Don’t animate opening applications from the Dock"
  defaults write com.apple.dock launchanim -bool false
  echo "Speed up Mission Control animations"
  defaults write com.apple.dock expose-animation-duration -float 0.1
  echo "Remove the auto-hiding Dock delay"
  defaults write com.apple.Dock autohide-delay -float 0
  echo "Remove the animation when hiding/showing the Dock"
  defaults write com.apple.dock autohide-time-modifier -float 0
  echo "Automatically hide and show the Dock"
  defaults write com.apple.dock autohide -bool true
  echo "Make Dock icons of hidden applications translucent"
  defaults write com.apple.dock showhidden -bool true

  echo "Modifying Safari & WebKit Settings"
  echo "Set Safari’s home page to about:blank for faster loading"
  defaults write com.apple.Safari HomePage -string "about:blank"
  echo "Prevent Safari from opening ‘safe’ files automatically after downloading"
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
  echo "Hide Safari’s bookmarks bar by default"
  defaults write com.apple.Safari ShowFavoritesBar -bool false
  echo "Disable Safari’s thumbnail cache for History and Top Sites"
  defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
  echo "Enable Safari’s debug menu"
  defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
  echo "Make Safari’s search banners default to Contains instead of Starts With"
  defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
  echo "Remove useless icons from Safari’s bookmarks bar"
  defaults write com.apple.Safari ProxiesInBookmarksBar ""
  echo "Enable the Develop menu and the Web Inspector in Safari"
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  echo "Add a context menu item for showing the Web Inspector in web views"
  defaults write -g WebKitDeveloperExtras -bool true
  echo "Enable the WebKit Developer Tools in the Mac App Store"
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true

  echo "Modifying iTunes Settings"
  echo "Disable the iTunes store link arrows"
  defaults write com.apple.iTunes show-store-link-arrows -bool false
  echo "Disable the Genius sidebar in iTunes"
  defaults write com.apple.iTunes disableGeniusSidebar -bool true
  echo "Disable the Ping sidebar in iTunes"
  defaults write com.apple.iTunes disablePingSidebar -bool true
  echo "Disable all the other Ping stuff in iTunes"
  defaults write com.apple.iTunes disablePing -bool true
  echo "Disable radio stations in iTunes"
  defaults write com.apple.iTunes disableRadio -bool true
  echo "Make ⌘ + F focus the search input in iTunes"
  defaults write com.apple.iTunes NSUserKeyEquivalents -dict-add "Target Search Field" "@F"

  echo "Modifying Mail Settings"
  echo "Disable send and reply animations in Mail.app"
  defaults write com.apple.mail DisableReplyAnimations -bool true
  defaults write com.apple.mail DisableSendAnimations -bool true
  echo "Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app"
  defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@U21a9"

  echo "Modifying Terminal Settings"
  echo "Enable \"focus follows mouse\" for Terminal.app and all X11 apps."
  echo "i.e. hover over a window and start typing in it without clicking first"
  defaults write com.apple.terminal FocusFollowsMouse -bool true
  defaults write org.x.X11 wm_ffm -bool true

  echo "Modifying Time Machine Settings"
  echo "Prevent Time Machine from prompting to use new hard drives as backup volume"
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  echo "Modifying Address Book, Dashboard, iCal, TextEdit, and Disk Utility Settings"
  echo "Enable the debug menu in Address Book"
  defaults write com.apple.addressbook ABShowDebugMenu -bool true
  echo "Enable Dashboard dev mode (allows keeping widgets on the desktop)"
  defaults write com.apple.dashboard devmode -bool true
  echo "Use plain text mode for new TextEdit documents"
  defaults write com.apple.TextEdit RichText -int 0
  echo "Open and save files as UTF–8 in TextEdit"
  defaults write com.apple.TextEdit PlainTextEncoding -int 4
  defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
  echo "Enable the debug menu in Disk Utility"
  defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
  defaults write com.apple.DiskUtility advanced-image-options -bool true

  echo "Modifying Energy Settings"
  echo "Stay on for 60 minutes with battery and 3 hours when plugged in"
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict "Display Sleep Timer" -int 60
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict "System Sleep Timer" -int 60
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "AC Power" -dict "System Sleep Timer" -int 180
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "AC Power" -dict "Display Sleep Timer" -int 180
  echo "Show battery percentage"
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"

  echo "Restart your computer to see all the changes."
fi

if false; then
  # todo: setup ControlPlane
  open "/Applications/ControlPlane.app"
fi

if [ -z "$GOOD_MORNING_RUN" ]; then
  echo "Use the command good_morning each day to stay up-to-date!"
fi

rm -f "$passfile"
unset passfile
unset passphrase
unset FIRST_RUN
# Update the environment repository last since a change to this script while
# in the middle of execution will break it.
# This is skipped if the good_morning bash alias was executed, in which case, a pull
# was made before setup.sh started.
if [ -n "$GOOD_MORNING_RUN" ]; then
  unset GOOD_MORNING_RUN
else
  echo "Almost done! Pulling latest for environment repository..."
  pushd "$ENVIRONMENT_REPO_ROOT" > /dev/null
  git pull && popd > /dev/null
fi
