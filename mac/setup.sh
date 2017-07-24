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
  read -r -p "$1" $2 < /dev/tty
  echo # echo newline after input
}

function promptsecret {
  read -r -s -p "$1: " $2 < /dev/tty
  echo # echo newline after input
}

if [ -e "$passfile" ]; then
  rm "$passfile"
fi
unset passfile
function sudoit {
  if [ -z "$passfile" ]; then
    passfile="$HOME/.temp_$(randstring32)"
    p=
    while [ -z "$p" ] || ! echo "$p" | sudo -S -p "" printf ""; do
      promptsecret "Password" p
    done
    encryptToFile "$p" "$passfile"
    unset p
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
  appPath="/Applications/$1.app"
  appPathUser="$HOME/Applications/$1.app"
  downloadPath="$HOME/Downloads/$1.dmg"
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

if /usr/bin/xcrun clang 2>&1 | grep license > /dev/null; then
  echo "Accepting the Xcode license..."
  sudoit xcodebuild -license accept
  echo "Installing Xcode command line tools..."
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDevice.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDeviceDevelopment.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
  xcode-select --install
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
  ssh-keygen -t rsa -b 4096 -C "$GITHUB_EMAIL"
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
if ! type "brew" > /dev/null 2> /dev/null; then
  yes '' | /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
  echo "Updating Homebrew..."
  brew update
  # steps from homebrew-core say to run brew update twice when troubleshooting
  # brew update
  echo "Upgrading Homebrew..."
  brew upgrade --cleanup
fi
brew doctor
# Having Homebrew issues? Run this command below.
# cd /usr/local && sudoit chown -R "$(whoami)" bin etc include lib sbin share var Frameworks


# Install brews
# shellcheck disable=SC2034
brews=(
  # java needs to be installed before maven, so bumping to top
  caskroom/cask/java # todo: current detection below doesn't see this, fix it

  certbot # For generating SSL certs with Let's Encrypt
  go
  git
  mas # Mac App Store command line interface - https://github.com/mas-cli/mas
  maven
  python
  python3
  shellcheck # shell script linting
  shpotify # Spotify shell CLI
  terraform
  transcrypt
  vim
  wget
  yarn # Recommended install method - https://yarnpkg.com/en/docs/install
)
brewtempfile="$HOME/brewlist.temp"
brew list > "$brewtempfile"
brew tap caskroom/cask
for brew in "${brews[@]}";
do
  if ! grep "$brew" "$brewtempfile" > /dev/null; then
    brew install "$brew"
  fi
done
rm "$brewtempfile"

if ! type "pip-review" > /dev/null 2> /dev/null; then
  pip2 install pip-review
fi

# Make sure user is signed into the Mac App Store
if ! mas account > /dev/null; then
  mas signin --dialog youremail@example.com
fi

# Install Xcode - https://itunes.apple.com/us/app/id497799835
masinstall 497799835 "Xcode"

if ! mas list | grep "441258766" > /dev/null; then
  # Install Magnet https://itunes.apple.com/us/app/id441258766
  echo "Magnet is an add-on for snappy window positioning."
  echo "It is optional, but it is dirt cheap and highly recommended."
  masinstall 441258766 "Magnet"
  askto "launch Magnet" "open /Applications/Magnet.app"
fi

# Install Slack https://itunes.apple.com/us/app/id803453959
# Currently using direct download option.
# masinstall 803453959 "Slack"
# Install OneDrive https://itunes.apple.com/us/app/id823766827
# masinstall 823766827 "OneDrive"

# Install Node Version Manager
NVM_VERSION="0.33.2"
# if nvm is already installed, load it in order to check its version
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  echo "Loading Node Version Manager..."
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh" > /dev/null
  echo "Node Version Manager Loaded."
fi

# https://github.com/creationix/nvm#install-script
if ! ( type "nvm" && nvm --version | grep "$NVM_VERSION" ) > /dev/null; then
  echo "Installing Node Version Manager v$NVM_VERSION"
  # run the install script
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v$NVM_VERSION/install.sh | bash
fi

echo "Checking local versions of node..."
LOCAL_NODE_LTS_VERSION=$(nvm version lts/*)
LATEST_NODE_LTS_VERSION=$(nvm version-remote --lts)
# Install highest Long Term Support build as a recommended "prod" node version
if [[ "$LOCAL_NODE_LTS_VERSION" != "$LATEST_NODE_LTS_VERSION" ]]; then
  nvm install --lts
  if [[ "$LOCAL_NODE_LTS_VERSION" != "N/A" ]]; then
    nvm reinstall-packages "$LOCAL_NODE_LTS_VERSION"
    nvm uninstall "$LOCAL_NODE_LTS_VERSION"
  fi
  # Update npm in the LTS build
  npm i -g npm
  # install some npm staples
  npm i -g npm-check-updates create-react-native-app flow-typed
fi
# Install latest version of node
LOCAL_NODE_VERSION=$(nvm version node)
LATEST_NODE_VERSION=$(nvm version-remote node)
if [[ "$LOCAL_NODE_VERSION" != "$LATEST_NODE_VERSION" ]]; then
  nvm install node
  if [[ "$LOCAL_NODE_VERSION" != "N/A" ]]; then
    nvm reinstall-packages "$LOCAL_NODE_VERSION"
    nvm uninstall "$LOCAL_NODE_VERSION"
  fi
  # Update npm in the LTS build
  npm i -g npm
  # install some npm staples
  npm i -g npm-check-updates create-react-native-app flow-typed
fi
echo "Node versions are up-to-date."

if ! pip-review | grep "Everything up-to-date" > /dev/null; then
  echo "Upgrading pip installed packages..."
  # ensure password for sudo is ready since we want to custom pass using the -H flag
  sudoit printf ""
  # call pip-review with python -m to enable updating pip-review itself
  # shellcheck disable=SC2002
  cat "$passfile" | sudo -H -S -p "" pip-review --auto
fi

if ! pip2 freeze | grep "awscli=" > /dev/null; then
  echo "Installing AWS CLI..."
  # ensure password for sudo is ready since we want to custom pass using the -H flag
  sudoit printf ""
  # passing -H to avoid warnings instead of using sudoit
  # shellcheck disable=SC2002
  cat "$passfile" | sudo -H -S -p "" pip2 install awscli
fi

if [ -n "$FIRST_RUN" ] && askto "review and install some recommended applications"; then
  # Install iTerm http://iterm2.com
  if ! [ -d "/Applications/iTerm.app" ]; then
    echo "Installing iTerm"
    curl -JL https://iterm2.com/downloads/stable/latest -o "$HOME/Downloads/iTerm.zip"
    sudoit unzip -q "$HOME/Downloads/iTerm.zip" -d "/Applications"
    rm "$HOME/Downloads/iTerm.zip"
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
  fi
  # Install OmniFocus 2
  # Beta builds may be available from - https://omnistaging.omnigroup.com/omnifocus-2/
  dmginstall "OmniFocus" https://www.omnigroup.com/download/latest/omnifocus/ "OmniFocus"
  # Install OmniGraffle
  dmginstall "OmniGraffle" https://www.omnigroup.com/download/latest/omnigraffle/ "OmniGraffle"
  # Install OmniOutliner 5
  # Beta builds may be available from - https://omnistaging.omnigroup.com/omnioutliner/
  dmginstall "OmniOutliner" https://www.omnigroup.com/download/latest/omnioutliner/ "OmniOutliner"
  # Install Google Chrome
  dmginstall "Google Chrome" https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg "Google Chrome"
  # Install Spotify
  dmginstall "Spotify" https://download.spotify.com/Spotify.dmg "Spotify"
  # Install Docker
  dmginstall "Docker" https://download.docker.com/mac/stable/Docker.dmg "Docker"
  # Install Charles
  dmginstall "Charles" https://www.charlesproxy.com/assets/release/4.1.2/charles-proxy-4.1.2.dmg "Charles Proxy v4.1.2"
  # Install Skype
  dmginstall "Skype" https://get.skype.com/go/getskype-macosx "Skype"
  # Install Android Studio
  dmginstall "Android Studio" https://dl.google.com/dl/android/studio/install/2.3.1.0/android-studio-ide-162.3871768-mac.dmg "Android Studio 2.3.1"
  # Install XMind
  dmginstall "XMind" http://dl2.xmind.net/xmind-downloads/xmind-8-update2-macosx.dmg "XMind"
  # Install ControlPlane
  dmginstall "ControlPlane" https://www.dropbox.com/s/lhuyzp1csx3f9cc/ControlPlane-1.6.6.dmg?dl=1 "ControlPlane"
  # Install Blue Jeans Scheduler
  dmginstall "Blue Jeans Scheduler for Mac" https://swdl.bluejeans.com/bluejeansformac/Blue+Jeans+Scheduler+for+Mac-1.0.208.dmg "Blue Jeans Scheduler for Mac"
  # Install KeeWeb
  dmginstall "KeeWeb" https://github.com/keeweb/keeweb/releases/download/v1.5.4/KeeWeb-1.5.4.mac.dmg "KeeWeb"

  # seeing if Excel is installed as crude check for Office
  if ! [ -d "/Applications/Microsoft Excel.app" ] && askto "install Microsoft Office"; then
    curl -JL https://go.microsoft.com/fwlink/?linkid=532572 -o "$HOME/Downloads/InstallOffice.pkg"
    sudoit installer -pkg "$HOME/Downloads/InstallOffice.pkg" -target /
    rm "$HOME/Downloads/InstallOffice.pkg"
  fi

  if ! [ -d "/Applications/Dropbox.app" ] && askto "install Dropbox"; then
    dmg="$HOME/Downloads/Dropbox.dmg"
    curl -JL https://www.dropbox.com/download?plat=mac -o "$dmg"
    hdiutil attach "$HOME/Downloads/Dropbox.dmg"
    open "/Volumes/Dropbox Installer/Dropbox.app"
    prompt "Hit Enter when Dropbox has finished installing..."
    diskutil unmount "Dropbox Installer"
    rm "$dmg"
  fi

  if ! [ -d "$HOME/Applications/Blue Jeans.app" ] && askto "install Blue Jeans"; then
    dmg="$HOME/Downloads/BlueJeans.dmg"
    curl -JL https://swdl.bluejeans.com/desktop/mac/launchers/BlueJeansLauncher_live_168.dmg -o "$dmg"
    hdiutil attach "$dmg"
    open "/Volumes/Blue Jeans Launcher/Blue Jeans Launcher.app"
    prompt "Hit Enter when Blue Jeans has finished installing..."
    diskutil unmount "Blue Jeans Launcher"
    rm "$dmg"
  fi

  if ! [ -d "/Applications/GPG Keychain.app" ] && askto "install GPG Suite"; then
    dmg="$HOME/Downloads/GPGSuite.dmg"
    curl -JL https://releases.gpgtools.org/GPG_Suite-2017.1b3-v2.dmg -o "$dmg"
    hdiutil attach "$dmg"
    sudoit installer -pkg "/Volumes/GPG Suite/Install.pkg" -target /
    diskutil unmount "GPG Suite"
    rm "$dmg"
  fi

  # Install YubiKey PIV Manager to enable unlock with a YubiKey
  if ! [ -d "/Applications/YubiKey PIV Manager.app" ] && askto "install YubiKey PIV Manager"; then
    pkg="$HOME/Downloads/YubiKeyPIVManager.pkg"
    curl -JL https://developers.yubico.com/yubikey-piv-manager/Releases/yubikey-piv-manager-1.4.1-mac.pkg -o "$pkg"
    sudoit installer -pkg "$pkg" -target /
    rm "$pkg"
  fi

  if ! [ -d "/Applications/Keyboard Maestro.app" ] && askto "install Keyboard Maestro"; then
    curl -JL https://files.stairways.com/keyboardmaestro-731.zip -o "$HOME/Downloads/KeyboardMaestro.zip"
    sudoit unzip -q "$HOME/Downloads/KeyboardMaestro.zip" -d "/Applications"
    rm "$HOME/Downloads/KeyboardMaestro.zip"
  fi

  if ! [ -d "$HOME/Applications/Atom.app" ] && askto "install Atom"; then
    curl -JL https://atom.io/download/mac -o "$HOME/Downloads/Atom.zip"
    sudoit unzip -q "$HOME/Downloads/Atom.zip" -d "$HOME/Applications"
    rm "$HOME/Downloads/Atom.zip"
  fi

  # Ensure Atom Shell Commands are installed
  if [ -d "/Applications/Atom.app" ] && ! type "apm" > /dev/null; then
    echo "Please install the Atom shell commands from inside Atom."
    echo "From the Atom menu bar, select Atom > Install Shell Commands."
    prompt "Hit Enter to open Atom..."
    open "/Applications/Atom.app"
    prompt "Select the menu item Atom > Install Shell Commands and hit Enter here when finished..."
    if ! apm list | grep "── vim-mode@" > /dev/null && askto "install Atom vim-mode"; then
      apm install vim-mode ex-mode
    fi
  fi

  if ! [ -d "$HOME/Applications/Atom Beta.app" ] && askto "install Atom Beta"; then
    curl -JL https://atom.io/download/mac?channel=beta -o "$HOME/Downloads/AtomBeta.zip"
    sudoit unzip -q "$HOME/Downloads/AtomBeta.zip" -d "$HOME/Applications"
    rm "$HOME/Downloads/AtomBeta.zip"
  fi

  if ! [ -d "$HOME/Applications/Visual Studio Code.app" ] && askto "install Visual Studio Code"; then
    curl -JL https://go.microsoft.com/fwlink/?LinkID=620882 -o "$HOME/Downloads/VSCode.zip"
    sudoit unzip -q "$HOME/Downloads/VSCode.zip" -d "$HOME/Applications"
    rm "$HOME/Downloads/VSCode.zip"
  fi

  if ! [ -d "$HOME/Applications/Visual Studio Code - Insiders.app" ] && askto "install Visual Studio Code Insiders"; then
    curl -JL https://go.microsoft.com/fwlink/?LinkId=723966 -o "$HOME/Downloads/VSCodeInsiders.zip"
    sudoit unzip -q "$HOME/Downloads/VSCodeInsiders.zip" -d "$HOME/Applications"
    rm "$HOME/Downloads/VSCodeInsiders.zip"
  fi

  if ! [ -d "$HOME/Applications/Beyond Compare.app" ] && askto "install Beyond Compare"; then
    curl -JL http://www.scootersoftware.com/BCompareOSX-4.2.2.22384.zip -o "$HOME/Downloads/BeyondCompare.zip"
    sudoit unzip -q "$HOME/Downloads/BeyondCompare.zip" -d "$HOME/Applications"
    rm "$HOME/Downloads/BeyondCompare.zip"
  fi

fi

if [ -n "$FIRST_RUN" ] && ! (defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall && \
  defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall && \
  defaults read /Library/Preferences/com.apple.commerce AutoUpdate && \
  defaults read /Library/Preferences/com.apple.commerce AutoUpdateRestartRequired) > /dev/null && \
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
  # Update all the Atom packages
  yes | apm update -c false
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

# Quick Look Generators
if ! [ -d /Library/QuickLook/Provisioning.qlgenerator ]; then
  echo "Installing iOS Provisioning Profile Quick Look Generator"
  curl -JL "https://github.com/chockenberry/Provisioning/releases/download/1.0.4/Provisioning-1.0.4.zip" -o "$HOME/Downloads/qlprovisioning.zip"
  unzip -q "$HOME/Downloads/qlprovisioning.zip" -d "$HOME/Downloads"
  sudoit mv "$HOME/Downloads/Provisioning-1.0.4/Provisioning.qlgenerator" /Library/QuickLook
  rm "$HOME/Downloads/qlprovisioning.zip"
  rm -rf "$HOME/Downloads/Provisioning-1.0.4/"
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

  echo "Modifying Dock & Hot Corner Settings"
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
  echo "Top right screen corner starts the screen saver"
  defaults write com.apple.dock wvous-tr-corner -int 5
  defaults write com.apple.dock wvous-tr-modifier -int 0

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

  echo "Restart your computer to see all the changes."
fi

if false; then
# todo: setup ControlPlane
open "/Applications/ControlPlane.app"
# todo: install Adobe Connect
https://www.adobe.com/go/adobeconnect_9_addin_mac
# adobeconnectaddin-installer.pkg
# todo: Install CoRD
# todo: Install Sketch
# todo: Install SourceTree
# todo: Install Framer
# todo: mute Skype sounds except messages and calls
# todo: change energy saver settings to not be so aggressive as it is annoying
# todo: Install the NDK from Android Studio
# todo: Clone the Bing desktop image downloader script repo and schedule script
# for a daily run.
# todo: setup daily refresh script
# todo: use dark menu bar and dock from general settings
# todo: set sidebar icon size to small
# todo: change setting show scroll bars when scrolling
# todo: turn off indicators for open apps since only open apps appear
# todo: turn off the slightly dim effect when disconnecting from power, this is more annoying than useful
# todo: suppress sponsor offers when updating Java from Java settings
fi

rm -f "$passfile"
unset passfile
unset passphrase
unset FIRST_RUN
# Update the environment repository last since a change to this script while
# in the middle of execution will break it.
echo "Almost done! Pulling latest for environment repository..."
pushd "$ENVIRONMENT_REPO_ROOT" > /dev/null
git pull && popd > /dev/null # DO NOT PUT ANYTHING BELOW THIS LINE
