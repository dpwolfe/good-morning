#!/usr/bin/env bash

# Do not exit immediately if a command exits with a non-zero status.
set +o errexit
# Print commands and their arguments as they are executed.
# Turn on for debugging
# set -o xtrace

function randstring32 {
  env LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1
}

if [ -z "$GOOD_MORNING_PASSPHRASE" ]; then
  GOOD_MORNING_PASSPHRASE="$(randstring32)"
fi
function encryptToFile {
  echo "$1" | openssl enc -aes-256-cbc -k $GOOD_MORNING_PASSPHRASE > "$2"
}

function decryptFromFile {
  openssl enc -aes-256-cbc -d -k $GOOD_MORNING_PASSPHRASE < "$1"
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

GOOD_MORNING_CONFIG_FILE="$HOME/.good_morning"
function getConfigValue {
  local val
  val="$( (grep -E "^$1=" -m 1 "$GOOD_MORNING_CONFIG_FILE" 2> /dev/null || echo "$1=$2") | head -n 1 | cut -d '=' -f 2-)"
  printf -- "%s" "$val"
}

function setConfigValue {
  # macOS uses Bash 3.x which does not support associative arrays yet
  # faking it is not worth the added complexity
  local keep_pass_for_session
  keep_pass_for_session="$(getConfigValue "keep_pass_for_session" "not-asked")" # "not-asked", "no" or "yes"
  local applied_cask_depends_on_fix
  applied_cask_depends_on_fix="$(getConfigValue "applied_cask_depends_on_fix" "no")" # "no" or "yes"
  local last_node_lts_installed
  last_node_lts_installed="$(getConfigValue "last_node_lts_installed")"
  local tempfile="$GOOD_MORNING_CONFIG_FILE""_temp"
  # crude validation
  if [[ "$1" == "keep_pass_for_session" ]] || \
    [[ "$1" == "applied_cask_depends_on_fix" ]] || \
    [[ "$1" == "last_node_lts_installed" ]]
  then
    export $1="$2"
  else
    echo "Warning: Tried to set an unknown config key: $1"
  fi
  echo "# This file stores settings and flags for the good-morning script." >> "$tempfile"
  echo "keep_pass_for_session=$keep_pass_for_session" >> "$tempfile"
  echo "applied_cask_depends_on_fix=$applied_cask_depends_on_fix" >> "$tempfile"
  echo "last_node_lts_installed=$last_node_lts_installed" >> "$tempfile"
  mv -f "$tempfile" "$GOOD_MORNING_CONFIG_FILE"
}

GOOD_MORNING_TEMP_FILE_PREFIX="$GOOD_MORNING_CONFIG_FILE""_temp_"
function sudoit {
  local sudoOpt
  # allow passing a flag or combination to sudo (example: -H)
  if [[ "$(echo '$1' | cut -c1)" == "-" ]]; then
    sudoOpt="$1"
    shift
  fi
  if ! [ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ] || ! decryptFromFile "$GOOD_MORNING_ENCRYPTED_PASS_FILE" | sudo -S -p "" printf ""; then
    GOOD_MORNING_ENCRYPTED_PASS_FILE="$GOOD_MORNING_TEMP_FILE_PREFIX$(randstring32)"
    local p=
    while [ -z "$p" ] || ! echo "$p" | sudo -S -p "" printf ""; do
      promptsecret "Password" p
    done
    encryptToFile "$p" "$GOOD_MORNING_ENCRYPTED_PASS_FILE"
  fi
  decryptFromFile "$GOOD_MORNING_ENCRYPTED_PASS_FILE" | sudo $sudoOpt -S -p "" "$@"
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
    rm -f "$downloadPath"
  fi
}

function checkPerms {
  echo "Checking directory permissions..."
  local dirs=(
    # Block of dirs that Homebrew needs the user to own for successful operation.
    # The redundancy of nested dirs is left here intentionally even though we use -R.
    /usr/local/bin
    /usr/local/Caskroom
    /usr/local/Cellar
    /usr/local/etc
    /usr/local/Frameworks
    /usr/local/Homebrew
    /usr/local/include
    /usr/local/lib
    /usr/local/lib/pkgconfig
    /usr/local/lib/python2.7/site-packages
    /usr/local/opt
    /usr/local/sbin
    /usr/local/share
    /usr/local/share/locale
    /usr/local/share/man
    /usr/local/var
    /usr/local/var/homebrew
    # Needed for pip installs without requiring sudo
    /Library/Python/2.7/site-packages
    /System/Library/Frameworks/Python.framework/Versions/2.7/share/doc
    /System/Library/Frameworks/Python.framework/Versions/2.7/share/man
    "$HOME/.pyenv"
  )
  local userPerm="$USER:wheel"
  for dir in "${dirs[@]}"; do
    if [ -d "$dir" ] && ! stat -f "%Su:%Sg" "$dir" 2> /dev/null | grep -E "^$userPerm$" > /dev/null; then
      echo "Setting ownership of $dir to $USER..."
      sudoit chown -R "$userPerm" "$dir"
    fi
  done
}
checkPerms

if type rvm &> /dev/null; then
  echo "Using default Ruby with rvm..."
  rvm use default > /dev/null
fi
echo "Checking for existence of xcode-install..."
if ! gem list --local | grep "xcode-install" > /dev/null; then
  echo "Installing xcode-install for managing Xcode..."
  # https://github.com/KrauseFx/xcode-install
  # The alternative install instructions must be used since there is not a working
  # compiler on the system at this point in the setup.
  curl -sL https://github.com/neonichu/ruby-domain_name/releases/download/v0.5.99999999/domain_name-0.5.99999999.gem -o ~/Downloads/domain_name-0.5.99999999.gem
  sudoit gem install ~/Downloads/domain_name-0.5.99999999.gem --no-document < /dev/tty
  sudoit gem install --conservative xcode-install --no-document < /dev/tty
  rm -f ~/Downloads/domain_name-0.5.99999999.gem
fi

function installXcode {
  local xcode_version="$1"
  local xcode_short_version="$(echo "$1" | sed -E 's/^([0-9|.]*).*/\1/')"
  # if [ -z "$FASTLANE_USER" ]; then
  #   prompt "Enter your Apple Developer ID: " fastlane_user
  #   FASTLANE_USER="$fastlane_user"
  # fi
  echo "Updating list of available Xcode versions..."
  xcversion update < /dev/tty
  echo "Installing Xcode $xcode_version..."
  xcversion install "$xcode_version" --force < /dev/tty # force makes upgrades from beta simple
  xcversion select "$xcode_short_version" < /dev/tty
  echo "Installing Xcode command line tools..."
  xcversion install-cli-tools < /dev/tty
  echo "Installing macOS SDK headers..."
  # These do need to be re-installed after an Xcode update. 
  sudoit installer -pkg /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg -target /
  echo "Cleaning up Xcode installers..."
  xcversion cleanup
  echo "Open up Settings > Software Update and install any updates."
  prompt "Hit Enter once those updates are completed or run this script again if a restart was needed first..."
}

function getLocalXcodeVersion {
  echo "$(/usr/bin/xcodebuild -version 2>&1 | grep Xcode | sed -E 's/Xcode ([0-9|.]*)/\1/')"
}

function checkXcodeVersion {
  local xcode_version="10.2.1"
  local xcode_build_version="10E1001"
  echo "Checking Xcode version..."
  if ! /usr/bin/xcode-select -p &> /dev/null; then
    installXcode "$xcode_version"
  else
    local local_version=getLocalXcodeVersion
    local local_build_version="$(/usr/bin/xcodebuild -version 2>&1 | grep Build | sed -E 's/Build version ([0-9A-Za-z]+)/\1/')"
    if [[ "$local_build_version" != "$xcode_build_version" ]]; then
      installXcode "$xcode_version"
      local new_local_version=getLocalXcodeVersion
      if [ -n "$local_version" ] && [[ "$local_version" != "$new_local_version" ]]; then
        echo "Uninstalling Xcode $local_version..."
        xcversion uninstall "$local_version" < /dev/tty
      fi
    fi
  fi
}
checkXcodeVersion

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
if ( [ -n "$gitHubEmailChanged" ] || ! [ -f "$HOME/.ssh/id_rsa.pub" ] ) && askto "create a GitHub SSH key for $GITHUB_EMAIL"; then
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

# This install is an artifact for first-run that is overridden by the brew cask install
# Some careful re-ordering will be able to eliminate this without breaking the first-run use case.
if ! [ -d "/Applications/GPG Keychain.app" ]; then
  echo "Installing GPG Suite..."
  dmg="$HOME/Downloads/GPGSuite.dmg"
  curl -JL https://releases.gpgtools.org/GPG_Suite-2017.3.dmg -o "$dmg"
  hdiutil attach "$dmg"
  sudoit installer -pkg "/Volumes/GPG Suite/Install.pkg" -target /
  diskutil unmount "GPG Suite"
  rm -f "$dmg"
  unset dmg
fi

function installRVM {
  echo "Installing RVM..."
  gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  curl -sSL https://get.rvm.io | bash -s stable --ruby
  # shellcheck source=/dev/null
  source "$HOME/.profile" # load rvm
  rvm cleanup all
  # enable rvm auto-update
  echo rvm_autoupdate_flag=2 >> ~/.rvmrc
  # enable rvm auto-reload on update
  echo rvm_auto_reload_flag=2 >> ~/.rvmrc
  # enable progress bar when downloading RVM / Rubies
  echo progress-bar >> ~/.curlrc
  # rvm loads in the profile file, not the same way with auto-dot files, so ignore next error
  echo rvm_silence_path_mismatch_check_flag=1 >> ~/.rvmrc
}

function checkRubyVersion {
  echo "Checking Ruby version..."
  latest_ruby_version="$(rvm list known 2> /dev/null | grep "\[ruby-" | tail -1 | tr -d '[]')"
  if [ "$(rvm list | grep 'No rvm rubies')" != "" ]; then
    rvm install "$latest_ruby_version" --default
    rvm cleanup all
  else
    current_ruby_version="$(ruby --version | sed -E 's/ ([0-9.]+)(p[0-9]+)?([^ ]*).*/-\1-\3/' | sed -E 's/-$//')"
    if [[ "$current_ruby_version" != "$latest_ruby_version" ]]; then
      echo "Upgrading RVM..."
      rvm get stable --auto
      # Upgrades of ruby versions disabled since there are gem incompatibilities.
      # At least it's not broken to just to install the latest version and migrate none of the gems.
      # echo "Upgrading Ruby from $current_ruby_version to $latest_ruby_version..."
      # rvm upgrade "$current_ruby_version" "$latest_ruby_version"
      echo "Installing latest Ruby version: $latest_ruby_version..."
      echo "Gems will not be migrated to provide you with a more reliable install experience."
      rvm install "$latest_ruby_version" --default
      rvm alias create default ruby
      rvm cleanup all
    fi
    unset current_ruby_version
    unset latest_ruby_version
  fi
}

if ! [ -s "$HOME/.rvm/scripts/rvm" ] && ! type rvm &> /dev/null; then
  installRVM
fi
checkRubyVersion

# ensure we are not using the system version
rvm use default > /dev/null

function updateGems {
  echo "Checking system ruby gem versions..."
  if [ "$(gem outdated)" ]; then
    echo "Updating ruby gems..."
    gem update --force --no-document
  fi
}
updateGems

function installGems {
  local gem_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""gem_list"
  local gems=(
    # bundler # dependency of xcode-install
    cocoapods
    # fastlane # dependency of xcode-install
    sqlint
    terraform_landscape
    xcode-install # Will also replace the other xcode-install gem that was installed while bootstrapping...
  )
  gem list --local > "$gem_list_temp_file"
  for gem in "${gems[@]}"; do
    if ! grep "$gem" "$gem_list_temp_file" > /dev/null; then
      echo "Installing $gem..."
      gem install "$gem" --no-document
    fi
  done
  rm -f "$gem_list_temp_file"
  # temp fix for fastlane having an internal version conflict with google-cloud-storage
  # remove once fastlane fixes this
  echo "Applying workaround to fix xcode-install..."
  echo "See https://github.com/fastlane/fastlane/issues/14242 to learn more."
  gem install google-cloud-storage -v 1.16.0 --no-document &> /dev/null
  gem uninstall google-cloud-storage -v 1.17.0 &> /dev/null
  gem uninstall google-cloud-storage -v 1.18.0 &> /dev/null
  gem uninstall google-cloud-storage -v 1.18.1 &> /dev/null
  gem uninstall google-cloud-storage -v 1.18.2 &> /dev/null
  # end temp fix
  gem cleanup
}
installGems

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
  gpg_todays_date=$(date -u +"%Y-%m-%d")
  gpg_expr="sec.*4096.*\/([[:xdigit:]]{16}) $gpg_todays_date.*"
  gpg_key_id=$(gpg --list-secret-keys --keyid-format LONG | grep -E "$gpg_expr" | sed -E "s/$gpg_expr/\1/")
  # copy the GPG public key for GitHub
  gpg --armor --export "$gpg_key_id" | pbcopy
  echo "GPG key copied to clipboard. GitHub will be opened next."
  echo "Click 'New GPG key' on GitHub when it opens and paste in the copied key."
  prompt "Hit Enter to open up GitHub... ($GITHUB_KEYS_URL)"
  open "$GITHUB_KEYS_URL"
  prompt "Hit Enter after the GPG key is saved on GitHub to continue..."
  # enable autos-signing of all the commits
  git config --global commit.gpgsign true
  git config --global user.signingkey "$gpg_key_id"
  # Silence output about needing a passphrase on each commit
  # echo 'no-tty' >> "$HOME/.gnupg/gpg.conf"
  echo "Finishing up GPG setup with a test..."
  echo "test" | gpg --clearsign # will prompt with dialog for passphrase to store in keychain
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
# Setup clone of good-morning repository
GOOD_MORNING_REPO_ROOT="$REPO_ROOT/good-morning"
if ! [ -d "$GOOD_MORNING_REPO_ROOT/.git" ]; then
  echo "Cloning good-morning repository..."
  git clone https://github.com/dpwolfe/good-morning.git "$GOOD_MORNING_REPO_ROOT"
  if [ -s "$HOME\.bash_profile" ]; then
    echo "Renaming previous ~/.bash_profile to ~/.old_bash_profile..."
    mv "$HOME\.bash_profile" "$HOME\.old_bash_profile_$(date +%Y%m%d%H%M%S)"
  fi
  echo "export REPO_ROOT=\"\$HOME/repo\"
source \"\$REPO_ROOT/good-morning/dotfiles/.bash_profile\"
if ! contains \$(pwd) \"\$REPO_ROOT\"; then cd \"\$REPO_ROOT\"; fi
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"  # load nvm
[ -s \"\$NVM_DIR/bash_completion\" ] && \. \"\$NVM_DIR/bash_completion\"  # load nvm bash_completion
[ -f /usr/local/etc/bash_completion ] && \. /usr/local/etc/bash_completion
if command -v pyenv 1> /dev/null 2>&1; then eval \"\$(pyenv init -)\"; fi
# RVM is sourced from the .profile file, make sure this happens last or RVM will complain
[ -s \"\$HOME/.profile\" ] && source \"\$HOME/.profile\"
" > "$HOME/.bash_profile"

  # copy some starter shell dot files
  cp "$GOOD_MORNING_REPO_ROOT/dotfiles/.inputrc" "$HOME/.inputrc"
  cp "$GOOD_MORNING_REPO_ROOT/dotfiles/.vimrc" "$HOME/.vimrc"
  cp -rf "$GOOD_MORNING_REPO_ROOT/dotfiles/.vim" "$HOME/.vim"
  # set flag to indicate this is the first run to turn on additional setup features
  FIRST_RUN=1
fi

# Homebrew taps - add those needed and remove obosoleted that can create conflicts (example: java8)
function checkBrewTaps {
  notaps=(
    caskroom/cask
    caskroom/versions
  )
  brew_tap_file="$GOOD_MORNING_TEMP_FILE_PREFIX""brew_tap"
  brew tap > "$brew_tap_file"
  for tap in "${notaps[@]}"; do
    if grep -E "^$tap$" "$brew_tap_file" > /dev/null; then
      brew untap "$tap"
    fi
  done
  taps=(
    wata727/tflint # tflint - https://github.com/wata727/tflint#homebrew
  )
  for tap in "${taps[@]}"; do
    if ! grep -E "^$tap$" "$brew_tap_file" > /dev/null; then
      brew tap "$tap"
    fi
  done
  rm -f "$brew_tap_file"
}

# Install homebrew - https://brew.sh
if ! type "brew" &> /dev/null; then
  yes '' | /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
  echo "Updating Homebrew..."
  checkBrewTaps
  brew update 2> /dev/null
  echo "Checking for outdated Homebrew formulas..."
  if [ "$(brew upgrade)" != "" ]; then
    BREW_CLEANUP_NEEDED=1
    # If there was any output from the cleanup task, assume a formula changed or was installed.
    # Homebrew Doctor can take a long time to run, so now running only after formula changes...
    echo "Running Hombrew Doctor..."
    brew doctor
  fi
  echo "Checking for outdated Homebrew Casks..."
  for outdatedCask in $(brew cask outdated | sed -E 's/^([^ ]*) .*$/\1/'); do
    echo "Upgrading $outdatedCask..."
    brew cask reinstall "$outdatedCask"
    BREW_CLEANUP_NEEDED=1
  done
fi

# Homebrew cask depends_on fix from: https://github.com/Homebrew/homebrew-cask/issues/58046
# The wireshark 3.0.0 install was the first cask that started to fail to update, but now succeeds
# with the following fix applied.
if [[ "$(getConfigValue 'applied_cask_depends_on_fix')" != "yes" ]]; then
  echo "Applying the Homebrew depends_on metadata fix from https://github.com/Homebrew/homebrew-cask/issues/58046..."
  /usr/bin/find "$(brew --prefix)/Caskroom/"*'/.metadata' -type f -name '*.rb' -print0 | /usr/bin/xargs -0 /usr/bin/perl -i -0pe 's/depends_on macos: \[.*?\]//gsm;s/depends_on macos: .*//g'
  setConfigValue "applied_cask_depends_on_fix" "yes"
fi

# Homebrew casks
brewCasks=(
  # android-platform-tools # uncomment if you need Android dev tools
  # android-studio # uncomment if you need Android dev tools
  # beyond-compare
  charles
  # controlplane # mac automation based on hardware events
  # cord # remote desktop into windows machines from macOS
  dbeaver-community
  # discord
  docker
  dropbox
  # etcher # Flash OS images to SD cards & USB drives, safely and easily.
  firefox
  # google-backup-and-sync
  google-chrome
  gpg-suite
  handbrake
  iterm2
  java8 # some things require java8 and I have not needed to install the latest java
  keeweb
  # keybase
  keyboard-maestro # keyboard macros
  # logitech-gaming-software
  microsoft-office
  minikube
  # omnifocus
  # omnigraffle
  # onedrive
  # opera
  # parallels
  postman
  provisionql # quick-look for iOS provisioning profiles
  qladdict
  qlcolorcode
  qlmarkdown
  rocket # utf-8 emoji quick lookup and insert in any macOS app
  # sketch
  skype
  slack
  # sourcetree
  spotify
  the-unarchiver
  transmission # open source BitTorrent client from https://github.com/transmission/transmission
  tunnelblick # connect to your VPN
  vanilla # hide menu icons on your mac
  virtualbox # A hypervisor like this is needed for Minikube
  visual-studio-code
  # visual-studio-code-insiders
  wavtap # https://github.com/pje/WavTap
  wireshark
  # To use WavTap you'll need to take some extra steps that shall not be automated.
  # Run this from the Recovery terminal: csrutil disable && reboot
  # Run this in a terminal: sudo nvram boot-args=kext-dev-mode=1
  # Reboot again and WavTap should appear in the sound devices menu.
  # xmind-zen
  # zoomus
)
brew_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""brew_list"
cask_collision_file="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_collision"
brew cask list > "$brew_list_temp_file"
# Uninstall Homebrew casks that conflict with this script or are now obsolete
# but may have been previously installed.
nobrewcasks=(
  insomniax # unmaintained
)
for brew in "${nobrewcasks[@]}"; do
  if grep -E "(^| )$brew($| )" "$brew_list_temp_file" > /dev/null; then
    brew cask uninstall --force "$brew"
  fi
done
# Install Homebrew casks
for cask in "${brewCasks[@]}"; do
  if ! grep -E "(^| )$cask($| )" "$brew_list_temp_file" > /dev/null; then
    echo "Installing $cask with Homebrew..."
    brew cask install "$cask" 2>&1 > /dev/null | grep "Error: It seems there is already an App at '.*'\." | sed -E "s/.*'(.*)'.*/\1/" > "$cask_collision_file"
    if [ -s "$cask_collision_file" ]; then
      # Remove non-brew installed version of app and retry.
      sudoit rm -rf "$(cat $cask_collision_file)"
      rm -f "$cask_collision_file"
      brew cask install "$cask"
    fi
    NEW_BREW_CASK_INSTALLS=1
    BREW_CLEANUP_NEEDED=1
  fi
done
rm -f "$cask_collision_file"
unset cask_collision_file
unset brewCasks

if [ -n "$BREW_CLEANUP_NEEDED" ]; then
  unset BREW_CLEANUP_NEEDED;
  echo "Cleaning up Homebrew cache..."
  brew cleanup -s # -s clears even the latest versions of uninstalled formulas and casks
fi

# Install brews
# shellcheck disable=SC2034
brews=(
  # ansible
  # azure-cli
  bash-completion
  # caddy
  # cassandra
  certbot # For generating SSL certs with Let's Encrypt
  # dialog # https://invisible-island.net/dialog/
  direnv # https://direnv.net/
  fd # https://github.com/sharkdp/fd
  # fish
  fx # https://github.com/antonmedv/fx
  fzf # https://github.com/junegunn/fzf
  git
  git-lfs
  go
  httpie # https://github.com/jakubroztocil/httpie
  jq
  # kops
  kubernetes-cli
  kubernetes-helm
  # maven
  openssl
  openssl@1.1
  p7zip # provides 7z command
  packer
  postgresql
  pyenv
  python # vim was failing load without this even though we have pyenv - 3/2/2018
  # redis
  ruby
  shellcheck # shell script linting
  terraform
  # terragrunt
  tflint
  tmux
  vegeta
  vim
  watchman
  # wireshark
  wget
  # yarn
  zsh
  zsh-completions
)
brew list > "$brew_list_temp_file"
for brew in "${brews[@]}"; do
  if ! grep -E "(^| )$brew($| )" "$brew_list_temp_file" > /dev/null; then
    brew install "$brew"
  fi
done
# Uninstall brews that conflict with this script
# but may have been previously installed.
nobrews=(
  wireshark # installed as cask
)
for brew in "${nobrews[@]}"; do
  if grep -E "(^| )$brew($| )" "$brew_list_temp_file" > /dev/null; then
    brew uninstall --force --ignore-dependencies "$brew"
  fi
done
rm -f "$brew_list_temp_file"
unset brews
unset nobrews
unset brew_list_temp_file
# Run this to set your shell to use fish (user, not root)
# chsh -s `which fish`

# Mojave users have to do this step for pyenv to install correctly:
# sudo installer -pkg /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg -target /

# prototype pyenv install code - need
if ! pyenv versions | grep "2\.7\.15" &> /dev/null; then
  CFLAGS="-I$(brew --prefix readline)/include -I$(brew --prefix openssl)/include" \
  LDFLAGS="-L$(brew --prefix readline)/lib -L$(brew --prefix openssl)/lib" \
  pyenv install 2.7.15
fi
if ! pyenv versions | grep "3\.7\.1" &> /dev/null; then
  CFLAGS="-I$(brew --prefix readline)/include -I$(brew --prefix openssl)/include" \
  LDFLAGS="-L$(brew --prefix readline)/lib -L$(brew --prefix openssl)/lib" \
  pyenv install 3.7.1
fi
pyenv global 3.7.1

function checkOhMyFish {
  if ! type "omf" &> /dev/null; then
    local temp_omf_install_file="$HOME/.good_morning_omf_install.temp"
    curl -L https://get.oh-my.fish > "$temp_omf_install_file"
    fish "$temp_omf_install_file" < /dev/tty
    rm -f "$temp_omf_install_file"
  else
    omf update
  fi
}
# checkOhMyFish - Need to find a way to avoid it immediately entering fish
# and stopping the rest of the script. Might try creating a process fork for this.

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

echo "Checking pip install..."
localpip="$(findpip)"
if [[ "$localpip" != "pip" ]] || ! pip &> /dev/null; then
  echo "Installing pip..."
  wget https://bootstrap.pypa.io/get-pip.py --output-document ~/get-pip.py
  python ~/get-pip.py --user
  rm -f ~/get-pip.py
else
  echo "Checking for update to pip..."
  pip install --upgrade pip --upgrade-strategy eager > /dev/null
fi
unset localpip

export PYCURL_SSL_LIBRARY=openssl
# Install pips in Python
piptempfile="$HOME/pipfreeze.temp"
$(findpip) freeze > "$piptempfile"
pips=(
  aws-shell
  awscli
  boto
  gitpython
  glances
  # gsutil # for programmatic access to Google Play Console reports
  lxml
  packaging
  pipdeptree
  pipenv
  pip-review
  pycurl
  requests
  virtualenv
)
for pip in "${pips[@]}"; do
  if ! grep -i "$pip==" "$piptempfile" &> /dev/null; then
    CFLAGS="-I$(brew --prefix openssl)/include" \
    CPPFLAGS="-I$(brew --prefix openssl)/include" \
    LDFLAGS="-L$(brew --prefix openssl)/lib" \
    "$(findpip)" install "$pip"
  fi
done
unset pips
rm -f $piptempfile
unset piptempfile

if ! pip-review | grep "Everything up-to-date" > /dev/null; then
  # echo "Upgrading pip installed packages..."
  # pip-review --auto
  # temporary workaround until we can ignore upgrading deps beyond what is supported (i.e. awscli and prompt-toolkit)
  pip install "prompt-toolkit<1.1.0,>=1.0.0" > /dev/null # fix previous upgrades that went to 2.0
fi

function upgradeNPM {
  echo "Checking Node.js $(node -v) global npm package versions..."
  # Upgrade all global packages other than npm to latest
  for package in $(npm -g outdated --parseable --depth=0 | cut -d: -f4); do
    echo "Upgrading global package $package for Node.js $(node -v)..."
    npm -g install "$package"
  done
  if ! type "ncu" &> /dev/null; then
    echo "Installing the npm-check-updates global package..."
    npm install npm-check-updates -g
  fi
}

function upgradeNode {
  local local_version="$1"
  local new_version="$2"
  local active_version # version user currently has active in then terminal
  active_version="$(nvm current)"

  if [[ "$(echo "$active_version" | cut -c1)" != "v" ]]; then
    active_version="N/A"
  fi

  if [[ "$local_version" != "$new_version" ]]; then
    local old_version="$local_version" # rename for readability
    nvm install "$new_version"
    echo "Clearing Node Version Manager cache..."
    nvm cache clear > /dev/null
    if [[ "$active_version" == "$old_version" ]]; then
      # In this case, the version that was active will be uninstalled.
      # Track the new one as the active_version
      active_version="$new_version"
    fi
    local reinstall_version
    reinstall_version="$(if [[ \"$old_version\" == \"N/A\" ]]; then echo "$active_version"; else echo "$old_version"; fi)"
    if [[ "$reinstall_version" != "N/A" ]] && [[ "$reinstall_version" != "$new_version" ]]; then
      echo "Installing global Node.js packages used by $reinstall_version into $new_version..."
      nvm reinstall-packages "$reinstall_version"
    fi
    upgradeNPM
  else
    nvm use "$local_version" > /dev/null
    upgradeNPM
  fi

  if [[ "$active_version" != "N/A" ]] && [[ "$active_version" != "$(nvm current)" ]]; then
    # Switch to the node version in use before any install or 'nvm use' command executed
    nvm use "$active_version" > /dev/null
  fi
}

# Install or Upgrade Node Version Manager. Start by getting the version number of the latest release.
nvm_version="$(curl 'https://api.github.com/repos/nvm-sh/nvm/releases?per_page=1' 2> /dev/null | grep '"tag_name"' | sed -E 's/.*"v([0-9.]+).*/\1/')"
# The following vars are populated after NVM is loaded
nvm_local_node=
nvm_latest_node=
nvm_local_lts=
nvm_latest_lts=
function loadNVM {
  echo "Loading Node Version Manager..."
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh" > /dev/null
  echo "Getting Node.js version information..."
  # cached because calling nvm version-remote takes a noticeable amount of time
  nvm_local_node="$(nvm version node)"
  nvm_latest_node="$(nvm version-remote node)"
  nvm_local_lts="$(nvm version lts/*)"
  if [[ "$nvm_local_lts" == "N/A" ]]; then
    # no local lts installed, or local lts is no longer the latest lts
    local last_node_lts_installed="$(getConfigValue 'last_node_lts_installed')"
    if [ -n "$last_node_lts_installed" ] && \
      nvm ls "$last_node_lts_installed" | grep "$last_node_lts_installed" > /dev/null
    then
      # lts node was previously installed by good-morning and it is still installed
      nvm_local_lts="$last_node_lts_installed"
    fi
  fi
  nvm_latest_lts="$(nvm version-remote --lts)"
}

function checkNodeVersion {
  local local_version="$1"
  local latest_version="$2"
  upgradeNode "$local_version" "$latest_version"
  if [[ "$local_version" != "N/A" ]] && \
    [[ "$local_version" != "$latest_version" ]] && \
    [[ "$local_version" != "$nvm_latest_lts" ]]; then
      echo "Uninstalling Node.js $local_version..."
      nvm uninstall "$local_version"
  fi
}

if ! [ -s "$HOME/.nvm/nvm.sh" ] || ! nvm --version | grep "$nvm_version" > /dev/null; then
  if [ -n "$NVM_DIR" ]; then
    mkdir -p "$NVM_DIR" # ensure directory exists if environment variable is set by existing bash_profile
  fi
  # https://github.com/creationix/nvm#install-script
  echo "Installing Node Version Manager v$nvm_version"
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v$nvm_version/install.sh | bash
  loadNVM
  echo "Installing latest Node.js..."
  checkNodeVersion "$nvm_local_node" "$nvm_latest_node"
  echo "Installing latest Node.js LTS..."
  checkNodeVersion "$nvm_local_lts" "$nvm_latest_lts"
  echo "Setting default Node.js version to be the latest..."
  nvm alias default node
else
  loadNVM
  echo "Checking version of installed Node.js..."
  checkNodeVersion "$nvm_local_node" "$nvm_latest_node"
  echo "Checking version of installed Node.js LTS..."
  checkNodeVersion "$nvm_local_lts" "$nvm_latest_lts"
fi
setConfigValue "last_node_lts_installed" "$nvm_latest_lts"
unset nvm_version
unset nvm_local_node
unset nvm_latest_node
unset nvm_local_lts
unset nvm_latest_lts

if [ -n "$FIRST_RUN" ] && askto "review and install some recommended applications"; then
  echo "Follow these steps to complete the iTerm setup:"
  echo "1. In Preferences > Profiles > Colors and select Tango Dark from the Color Presets... drop down."
  echo "2. In Prefernces > Profiles > Terminal, set the iTerm buffer scroll back to 100000."
  echo "3. Run the Install Shell Integration command from the iTerm2 menu."
  echo "4. Use iTerm instead of Terminal from now on. Learn more here: https://iterm2.com/"
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

# Surface some hidden utility apps that are not available in Spotlight Search
function linkUtil {
  local linkPath="/Applications/Utilities/$(echo "$1" | sed -E "s/.*\/(.*\.app)/\1/")"
  if [ -d "$1" ] && ! [ -L "$linkPath" ]; then
    echo "Creating $linkPath symlink..."
    sudoit ln -s "$1" "$linkPath"
  fi
}
linkUtil "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"

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
  echo "Do not add recently used apps to the dock automatically."
  defaults write com.apple.dock show-recents -bool false
  echo "Enable tap to click on trackpad"
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  echo "Bump up the trackpad speed a couple notches"
  defaults write -g com.apple.trackpad.scaling 2
  echo "Turn off the annoying auto-capitalize while typing"
  defaults write -g NSAutomaticCapitalizationEnabled -bool false
  echo "Turn off dash substitution"
  defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
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
  echo "Disable automatic quote substitution as it inevitably happens when writing JavaScript or JSON"
  defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
  echo "Disable the crash reporter"
  defaults write com.apple.CrashReporter DialogType -string "none"
  echo "Set Help Viewer windows to non-floating mode"
  defaults write com.apple.helpviewer DevMode -bool true
  echo "Reveal IP address, hostname, OS version, etc. when clicking the clock in the login window"
  sudoit defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
  echo "Check for software updates daily, not just once per week"
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

  echo "Modifying Mouse & Trackpad Settings"
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
  echo "Trackpad: 'Tap with three fingers' instead of 'Force click with one finger' for 'Look up' feature"
  defaults -currentHost write -g com.apple.trackpad.forceClick -int 0
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 2

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
  defaults write -g WebAutomaticSpellingCorrectionEnabled -bool false
  echo "Turn off typing suggestions in the touch bar"
  defaults write -g NSAutomaticTextCompletionEnabled -bool false

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
  echo "Finder: show path bar"
  defaults write com.apple.finder ShowPathbar -bool true
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
  echo "Turn off the boot sound effect"
  sudoit nvram SystemAudioVolume=" "

  echo "Restart your computer to see all the changes."
fi

if [ -z "$GOOD_MORNING_RUN" ]; then
  echo "Use the command good-morning each day to stay up-to-date!"
fi

function cleanupTempFiles {
  local good_morning_pass_file_temp="$HOME/.good_morning_pass_file" # lacks 'temp' in name to bypass deletion if kept
  # Clean-up the encrypted pass file used for sudo calls unless disabled by the config.
  if [[ "$(getConfigValue 'keep_pass_for_session')" == "yes" ]] && [ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]; then
    mv "$GOOD_MORNING_ENCRYPTED_PASS_FILE" "$good_morning_pass_file_temp"
  fi
  # A glob file deletion is about to happen, proceed with excessive caution.
  if [[ "$GOOD_MORNING_TEMP_FILE_PREFIX" == "$HOME/.good_morning_temp_" ]]; then
    rm -f "$GOOD_MORNING_TEMP_FILE_PREFIX"*
  else
    echo "Warning: Unexpected pass file prefix. Temp file clean-up is incomplete."
  fi
  # Move the encrypted pass file back post cleanup if deleting it was disabled by the config.
  if [[ "$(getConfigValue 'keep_pass_for_session')" == "yes" ]] && [ -e "$good_morning_pass_file_temp" ]; then
    mv "$good_morning_pass_file_temp" "$GOOD_MORNING_ENCRYPTED_PASS_FILE"
  fi
}

function cleanupEnvVars {
  unset FIRST_RUN
  unset GITHUB_EMAIL
  unset GITHUB_KEYS_URL
  unset GITHUB_NAME
  unset GOOD_MORNING_CONFIG_FILE
  unset GOOD_MORNING_TEMP_FILE_PREFIX
  unset GOOD_MORNING_REPO_ROOT

  if [[ "$(getConfigValue 'keep_pass_for_session')" != "yes" ]]; then
    unset GOOD_MORNING_ENCRYPTED_PASS_FILE
    unset GOOD_MORNING_PASSPHRASE
  fi
}

# Update the good-morning repository last since a change to this script while
# in the middle of execution will break it.
# This is skipped if the good-morning bash alias was executed, in which case, a pull
# was made before good-morning.sh started.
function cleanupGoodMorning {
  if [ -n "$GOOD_MORNING_RUN" ]; then
    unset GOOD_MORNING_RUN
    local keep_pass_for_session
    keep_pass_for_session="$(getConfigValue 'keep_pass_for_session' 'not-asked')"
    if ( [ -z "$keep_pass_for_session" ] || [[ "$keep_pass_for_session" == "not-asked" ]] ) && [ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]; then
      if askto "always be prompted for your password if needed when you run good-morning again in the same session"; then
        setConfigValue "keep_pass_for_session" "no"
      else
        setConfigValue "keep_pass_for_session" "yes"
      fi
    fi
    cleanupTempFiles
    cleanupEnvVars
  else
    echo "Almost done! Pulling latest for good-morning repository..."
    cleanupTempFiles
    pushd "$GOOD_MORNING_REPO_ROOT" > /dev/null
    cleanupEnvVars && git pull && popd > /dev/null
  fi
}
cleanupGoodMorning
