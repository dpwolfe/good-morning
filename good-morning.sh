#!/usr/bin/env bash

# Do not exit immediately if a command exits with a non-zero status.
set +o errexit
# Print commands and their arguments as they are executed.
# Turn on for debugging
# set -o xtrace

bold=
normal=
if type tput &> /dev/null && test -t 1; then
  ncolors=$(tput colors)
  if test -n "$ncolors" && test "$ncolors" -ge 8; then
    bold=$(tput bold)
    normal=$(tput sgr0)
  fi
fi

function errcho {
  red='\033[0;31m'
  nc='\033[0m'
  echo -e "${bold}${red}ERROR: $*${nc}${normal}" >&2
}

function eccho {
  local light_blue='\033[1;34m'
  local nc='\033[0m'
  echo -e "${bold}${light_blue}$*${nc}${normal}"
}

function randstring32 {
  env LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1
}

if [[ -z "$GOOD_MORNING_PASSPHRASE" ]]; then
  GOOD_MORNING_PASSPHRASE="$(randstring32)"
fi
function encryptToFile {
  echo "$1" | openssl enc -aes-256-cbc -pbkdf2 -k "$GOOD_MORNING_PASSPHRASE" > "$2"
}

function decryptFromFile {
  openssl enc -aes-256-cbc -pbkdf2 -d -k "$GOOD_MORNING_PASSPHRASE" < "$1"
}

function askto {
  eccho "Do you want to $1? $3"
  read -r -n 1 -p "(Y/n) " yn < /dev/tty;
  echo # echo newline after input
  # shellcheck disable=SC2091
  case $yn in
    y|Y ) $($2); return 0;;
    n|N ) return 1;;
  esac
}

function prompt {
  if [[ -n "$2" ]]; then
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
    # shellcheck disable=SC2086
    export $1="$2"
  else
    errcho "Warning: Tried to set an unknown config key: $1"
  fi
  {
    echo "# This file stores settings and flags for the good-morning script.";
    echo "keep_pass_for_session=$keep_pass_for_session";
    echo "applied_cask_depends_on_fix=$applied_cask_depends_on_fix";
    echo "last_node_lts_installed=$last_node_lts_installed";
  } > "$tempfile"
  mv -f "$tempfile" "$GOOD_MORNING_CONFIG_FILE"
}

GOOD_MORNING_TEMP_FILE_PREFIX="$GOOD_MORNING_CONFIG_FILE""_temp_"
function sudoit {
  local sudoOpt
  # allow passing a flag or combination to sudo (example: -H)
  if [[ "$(echo "$1" | cut -c1)" == "-" ]]; then
    sudoOpt="$1"
    shift
  fi
  if ! [[ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]] || ! decryptFromFile "$GOOD_MORNING_ENCRYPTED_PASS_FILE" | sudo -S -p "" printf ""; then
    GOOD_MORNING_ENCRYPTED_PASS_FILE="$GOOD_MORNING_TEMP_FILE_PREFIX$(randstring32)"
    local p=
    while [[ -z "$p" ]] || ! echo "$p" | sudo -S -p "" printf ""; do
      promptsecret "Password" p
    done
    encryptToFile "$p" "$GOOD_MORNING_ENCRYPTED_PASS_FILE"
  fi
  # shellcheck disable=SC2086
  decryptFromFile "$GOOD_MORNING_ENCRYPTED_PASS_FILE" | sudo $sudoOpt -S -p "" "$@"
}

function dmginstall {
  local appPath="/Applications/$1.app"
  local appPathUser="$HOME/Applications/$1.app"
  local downloadPath="$HOME/Downloads/$1.dmg"
  # only offer to install if not installed in either the user or "all users" locations
  if ! [[ -d "$appPath" ]] && ! [[ -d "$appPathUser" ]] && askto "install $1"; then
    curl -JL "$2" -o "$downloadPath"
    yes | hdiutil attach "$downloadPath" > /dev/null
    # install in the "all users" location
    sudoit ditto "/Volumes/$3/$1.app" "$appPath"
    diskutil unmount "$3" > /dev/null
    rm -f "$downloadPath"
  fi
}

function getOSVersion {
  sw_vers | grep -E "ProductVersion" | sed -E "s/^.*(10\.[.0-9]+)/\1/"
}

function checkOSRequirement {
  if getOSVersion | grep -qvE ' 1(0\.15|1\.)'; then
    errcho "Good Morning must be run on either macOS 10.15 (Catalina) or 11.x (Big Sur)."
    exit 1
  fi
}

function checkPerms {
  eccho "Checking directory permissions..."
  # shellcheck disable=SC2207
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
    /usr/local/share/man/*
    /usr/local/var
    /usr/local/var/homebrew
    # Needed for pip installs without requiring sudo
    /Library/Python/2.7/site-packages
    /Library/Ruby/Gems/*
    /Library/Ruby/Site/*
    /System/Library/Frameworks/Python.framework/Versions/2.7/share/doc
    /System/Library/Frameworks/Python.framework/Versions/2.7/share/man
    "$HOME/.pyenv"
    # /Applications/*.app
  )
  local userPerm="$USER:wheel"
  for dir in "${dirs[@]}"; do
    if [[ -d "$dir" ]] && ! stat -f "%Su:%Sg" "$dir" 2> /dev/null | grep -qE "^$userPerm$"; then
      eccho "Setting ownership of $dir to $USER..."
      sudoit chown -R "$userPerm" "$dir"
    fi
  done
  # "Allow apps downloaded from: Anywhere" for app backwards compatibility with macOS 10.15 Catalina
  # Otherwise, some apps and quicklook extensions don't switch to the Allowed state properly from
  # the Security & Privacy settings.
  if spctl --status | grep -q "assessments enabled" && getOSVersion | grep -q "10.15"; then
    sudoit spctl --master-disable
  fi
}
checkPerms

function updateGems {
  eccho "Checking Ruby system gem versions..."
  gem update --system --force --no-document
  eccho "Checking Ruby gem versions..."
  local outdated
  outdated="$(gem outdated | grep -Ev 'google-cloud-storage' | sed -E 's/[ ]*\([^)]*\)[ ]*/ /g')"
  if [[ -n "$outdated" ]]; then
    eccho "Updating these Ruby gems:"
    eccho "$outdated"
    # shellcheck disable=SC2086
    gem update $outdated --force --no-document
  fi
}

if ! type rvm &> /dev/null || rvm list | grep -q 'No rvm rubies'; then
  eccho "Using macOS Ruby."
else
  eccho "Using RVM's default Ruby..."
  rvm use default
fi
eccho "Checking for existence of xcode-install..."
if ! gem list --local | grep -q "xcode-install"; then
  eccho "Installing xcode-install for managing Xcode..."
  # https://github.com/KrauseFx/xcode-install
  # The alternative install instructions must be used since there is not a working
  # compiler on the system at this point in the setup.
  curl -sL https://github.com/neonichu/ruby-domain_name/releases/download/v0.5.99999999/domain_name-0.5.99999999.gem -o ~/Downloads/domain_name-0.5.99999999.gem
  sudoit gem install ~/Downloads/domain_name-0.5.99999999.gem --no-document < /dev/tty
  sudoit gem install --conservative xcode-install --no-document < /dev/tty
  rm -f ~/Downloads/domain_name-0.5.99999999.gem
fi

function ensureXcodeInstallUserSet {
  if [[ -z "$XCODE_INSTALL_USER" ]]; then
    local xcode_install_user
    eccho "Your Apple Developer ID is required to install Xcode and essential build tools."
    eccho "The Apple ID you use must have accepted the Apple Developer Agreement."
    eccho "You can do this by signing in or creating a new Apple ID at https://developer.apple.com/account/"
    prompt "Enter your Apple Developer ID: " xcode_install_user
    export XCODE_INSTALL_USER="$xcode_install_user"
    if [[ -f ~/.bash_profile ]]; then
      # append to .bash_profile since unlikely to change
      echo "export XCODE_INSTALL_USER=\"$xcode_install_user\"" >> ~/.bash_profile
    fi
  fi
}

function installXcode {
  local xcode_version="$1"
  local xcode_build_version="$2"
  local xcode_short_version
  xcode_short_version="$(echo "$1" | sed -E 's/^([0-9|.]*).*/\1/')"
  ensureXcodeInstallUserSet
  eccho "Updating list of available Xcode versions..."
  xcversion update < /dev/tty
  eccho "Installing Xcode $xcode_version..."
  xcversion install "$xcode_version" --force < /dev/tty # force makes upgrades from beta a simple process
  xcversion select "$xcode_short_version" < /dev/tty
  eccho "Installing Xcode command line tools..."
  xcversion install-cli-tools < /dev/tty
  # link to the header file locations
  sudoit ln -s /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/* /usr/local/include/
  # run cleanup if the install was successful
  if [[ "$(getLocalXcodeBuildVersion)" = "$xcode_build_version" ]]; then
    eccho "Cleaning up Xcode installers..."
    xcversion cleanup
  fi
}

function getLocalXcodeVersion {
  /usr/bin/xcodebuild -version 2>&1 | grep "Xcode" | sed -E 's/Xcode ([0-9|.]*)/\1/'
}

function getLocalXcodeBuildVersion {
  /usr/bin/xcodebuild -version 2>&1 | grep "Build" | sed -E 's/Build version ([0-9A-Za-z]+)/\1/'
}

function checkXcodeVersion {
  local xcode_version="12.1" # do not append prerelease names such as "Beta" to this version number.
  local xcode_prerelease_stage="" # leave blank when not a beta or leave a trailing space at the end if it is (e.g "Beta 1 ")
  local xcode_build_version="11E503a"
  eccho "Checking Xcode version..."
  if ! /usr/bin/xcode-select --print-path &> /dev/null || \
      ! [[ -d "$(/usr/bin/xcode-select --print-path)" ]] || \
      [[ "$(/usr/bin/xcode-select --print-path)" = "/Library/Developer/CommandLineTools" ]]; then
      # One of these cases is true, so an install is necessary (no prompt).
      # 1) Calling xcode-select failed for any reason
      # 2) xcode-select is pointing to a Developer directory that does not exist
      # 3) xcode-select is pointing to the default /Library location when no Xcode is installed
    installXcode "$xcode_version" "$xcode_build_version"
  else
    # Xcode appears to be installed. Check to see if an upgrade option should be offered.
    local local_version
    local local_build_version
    local_version="$(getLocalXcodeVersion)"
    local_build_version="$(getLocalXcodeBuildVersion)"
    if [[ "$local_build_version" < "$xcode_build_version" ]] \
      && askto "upgrade Xcode to $xcode_version $xcode_prerelease_stage(Build $xcode_build_version) from $local_version (Build $local_build_version)..."; then

      installXcode "$xcode_version" "$xcode_build_version"
      local new_local_version
      new_local_version="$(getLocalXcodeVersion)"
      # If there was a previous version installed, but it wasn't a beta which will have the same version number...
      if [[ -n "$local_version" ]] && [[ "$local_version" != "$new_local_version" ]]; then
        eccho "Uninstalling Xcode $local_version (Build $local_build_version)..."
        xcversion uninstall "$local_version" < /dev/tty
      fi
    fi
  fi
}
checkXcodeVersion

if /usr/bin/xcrun clang 2>&1 | grep -q "license"; then
  eccho "Accepting the Xcode license..."
  sudoit xcodebuild -license accept
  eccho "Installing Xcode packages..."
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDevice.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDeviceDevelopment.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
fi

GIT_EMAIL="$(git config --global --get user.email)"
if [[ -z "$GIT_EMAIL" ]]; then
  prompt "Enter the email address you use for git commits: " GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
fi
GIT_NAME="$(git config --global --get user.name)"
if [[ -z "$GIT_NAME" ]]; then
  prompt "Enter the full name you use for git commits: " GIT_NAME
  git config --global user.name "$GIT_NAME"
fi
# Generate a new SSH key for GitHub https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/

if ! [[ -f "$HOME/.ssh/id_rsa.pub" ]] && askto "create an SSH key for $GIT_EMAIL"; then
  eccho "Generating SSH key to be stored at $HOME/.ssh/id_rsa ..."
  ssh-keygen -t rsa -b 4096 -C "$GIT_EMAIL" < /dev/tty
  eccho "Starting ssh-agent ..."
  eval "$(ssh-agent -s)"
  # automatically load the keys and store passphrases in your keychain
  eccho "Initializing your ~/.ssh/config"
  echo "Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile \"$HOME/.ssh/id_rsa\"" >> "$HOME/.ssh/config"
  # add your ssh key to ssh-agent
  ssh-add -K "$HOME/.ssh/id_rsa"
  if askto "add your SSH key to GitHub or other source control provider"; then
    # copy public ssh key to clipboard for pasting on GitHub
    pbcopy < "$HOME/.ssh/id_rsa.pub"
    eccho "The public key is now in your clipboard."
    GITHUB_KEYS_URL="https://github.com/settings/keys"
    if askto "open up GitHub's settings page for adding SSH keys"; then
      eccho "GitHub will be opened next. Sign-in with $GIT_EMAIL if you have not already."
      eccho "Click 'New SSH key' and paste in the copied key."
      prompt "Hit Enter to open $GITHUB_KEYS_URL..."
      open "$GITHUB_KEYS_URL"
      prompt "Hit Enter to continue after the SSH key is saved on GitHub..."
    else
      eccho "With your new public key in the clipboard, take a moment to add it to all of the"
      eccho "source control providers that you use, such as BitBucket or GitLab."
      prompt "Hit Enter to continue running the script..."
    fi
  fi
fi

# This install is an artifact for first-run that is overridden by the brew install
# Some careful re-ordering will be able to eliminate this without breaking the first-run use case.
gpg_suite_new_install=
if ! [[ -d "/Applications/GPG Keychain.app" ]] \
    && askto "install GPG Suite"; then
  eccho "Installing GPG Suite..."
  dmg="$HOME/Downloads/GPGSuite.dmg"
  curl -JL https://releases.gpgtools.org/GPG_Suite-2019.1_83.dmg -o "$dmg"
  hdiutil attach "$dmg"
  sudoit installer -pkg "/Volumes/GPG Suite/Install.pkg" -target /
  diskutil unmount "GPG Suite"
  rm -f "$dmg"
  unset dmg
  gpg_suite_new_install=1
fi

rvm_version=1.29.12
function installRVM {
  eccho "Installing RVM..."
  if type rvm &> /dev/null; then
    gpg2 --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  fi
  curl -sSL https://get.rvm.io | bash -s $rvm_version --ruby
  rvm rubygems latest --force # gets updated immediately, but fixes issues that show up when running xcversion
  # shellcheck source=/dev/null
  source "$HOME/.profile" # load rvm
  rvm cleanup all
  # enable rvm auto-update
  # echo rvm_autoupdate_flag=2 >> ~/.rvmrc
  # enable rvm auto-reload on update
  echo rvm_auto_reload_flag=2 >> ~/.rvmrc
  # enable progress bar when downloading RVM / Rubies
  echo progress-bar >> ~/.curlrc
  # rvm loads in the profile file, not the same way with auto-dot files, so ignore next error
  echo rvm_silence_path_mismatch_check_flag=1 >> ~/.rvmrc
}

function checkRubyVersion {
  if rvm version | grep -qv "$rvm_version"; then
    eccho "Upgrading RVM to $rvm_version..."
    # hard-coded since auto upgrade check hits GitHub's rate limits too frequently
    rvm get $rvm_version --auto-dotfiles
  fi
  eccho "Checking Ruby version..."
  # rvm list known is only showing 3.0.0, which is outdated. Hard-coding until there is a better way found.
  # latest_ruby_version="$(rvm list known 2> /dev/null | tr -d '[]' | grep -E "^ruby-[0-9.]+$" | tail -1)"
  latest_ruby_version="ruby-3.2.2"
  if rvm list | grep -q 'No rvm rubies'; then
    rvm install "$latest_ruby_version"
    rvm alias create default ruby "$latest_ruby_version"
    rvm rubygems latest --force # gets updated immediately, but fixes issues that show up when running xcversion
    rvm cleanup all
  else
    current_ruby_version="$(ruby --version | sed -E 's/ ([0-9.]+)(p[0-9]+)?([^ ]*).*/-\1-\3/' | sed -E 's/-$//')"
    if [[ "$current_ruby_version" != "$latest_ruby_version" ]]; then
      eccho "Upgrading Ruby from $current_ruby_version to $latest_ruby_version..."
      eccho "The RVM upgrade feature is not used to provide you a more reliable experience."
      rvm install "$latest_ruby_version"
      rvm rubygems latest --force # gets updated immediately, but fixes issues that show up when running xcversion
      rvm cleanup all
      eccho "The previous version of Ruby is still available by running 'rvm use $current_ruby_version'."
      rvm alias create default ruby "$latest_ruby_version"
    fi
    unset current_ruby_version
    unset latest_ruby_version
  fi
}

if ! [[ -s "$HOME/.rvm/scripts/rvm" ]] && ! type rvm &> /dev/null; then
  installRVM
fi

checkRubyVersion

# ensure we are not using the system version
rvm use default > /dev/null
updateGems

function installGems {
  local gem_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""gem_list"
  local gems=(
    cocoapods
    # fastlane # installed as dependency of xcode-install
    sqlint
    terraform_landscape
    xcode-install # Will also replace the other xcode-install gem that was installed while bootstrapping...
  )
  gem list --local > "$gem_list_temp_file"
  for gem in "${gems[@]}"; do
    if ! grep -q "$gem" "$gem_list_temp_file"; then
      eccho "Installing $gem..."
      gem install "$gem" --no-document
    fi
  done
  rm -f "$gem_list_temp_file"
  # temp fix for fastlane having an internal version conflict with google-cloud-storage
  # remove once fastlane fixes this
  # eccho "Applying workaround to fix xcode-install..."
  # eccho "See https://github.com/fastlane/fastlane/issues/14242 to learn more."
  # gem uninstall google-cloud-storage --all --force &> /dev/null
  # gem install google-cloud-storage -v 1.16.0 --no-document &> /dev/null
  # end temp fix
  gem cleanup
}
installGems

if (( gpg_suite_new_install == 1 )); then
  unset gpg_suite_new_install
  eccho "Creating a GPG key for you to use when signing commits is an excellent way to guarantee the"
  eccho "integrity of your code changes for others."
  eccho "Learn more about this here: https://git-scm.com/book/tr/v2/Git-Tools-Signing-Your-Work"
  eccho "Learn about GitHub's use here: https://help.github.com/articles/generating-a-new-gpg-key/"
  if askto "create a GPG signing key for signing your git commits"; then
    eccho "Generating a GPG key for signing Git operations..."
    promptsecret "Enter a passphrase for the GPG key" GPG_PASSPHRASE
    gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GIT_NAME
Name-Comment: Git signing key
Name-Email: $GIT_EMAIL
Expire-Date: 2y
Passphrase: $GPG_PASSPHRASE
%commit
EOF
    unset GPG_PASSPHRASE

    eccho "Signing key created."
    gpg_todays_date=$(date -u +"%Y-%m-%d")
    gpg_expr="sec.*4096.*\/([[:xdigit:]]{16}) $gpg_todays_date.*"
    gpg_key_id=$(gpg --list-secret-keys --keyid-format LONG | grep -E "$gpg_expr" | sed -E "s/$gpg_expr/\1/")
    # copy the GPG public key for GitHub
    gpg --armor --export "$gpg_key_id" | pbcopy
    eccho "Your new GPG key is copied to the clipboard."
    if askto "open up GitHub's settings page for adding GPG keys"; then
      eccho "After GitHub opens, click 'New GPG key' and paste in the copied key."
      prompt "Hit Enter to open up $GITHUB_KEYS_URL ..."
      open "$GITHUB_KEYS_URL"
      prompt "Hit Enter to continue after you have saved the GPG key on GitHub..."
    fi
    eccho "Enabling auto-signing of all commits and other git actions..."
    git config --global commit.gpgsign true
    git config --global user.signingkey "$gpg_key_id"
    eccho "Finishing up GPG setup with a test that will complete the setup..."
    eccho "Please accept the GPG related dialog box if it opens."
    echo "test" | gpg --clearsign # will prompt with dialog for passphrase to store in keychain
  fi
fi

# Pick a default repo root unless one is already set
if [[ -z "${REPO_ROOT+x}" ]]; then
  REPO_ROOT="$HOME/repo"
fi
# Create local repository root
if ! [[ -d "$REPO_ROOT" ]]; then
  eccho "Creating $REPO_ROOT"
  mkdir -p "$REPO_ROOT"
fi

# Setup clone of good-morning repository
GOOD_MORNING_REPO_ROOT="$REPO_ROOT/good-morning"
if ! [[ -d "$GOOD_MORNING_REPO_ROOT/.git" ]]; then
  eccho "Cloning good-morning repository..."
  git clone https://github.com/dpwolfe/good-morning.git "$GOOD_MORNING_REPO_ROOT"
  if [[ -s "$HOME\.bash_profile" ]]; then
    eccho "Renaming previous ~/.bash_profile to ~/.old_bash_profile..."
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
  ensureXcodeInstallUserSet

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
    homebrew/cask-drivers
    caskroom/caskroom
    caskroom/versions
  )
  brew_tap_file="$GOOD_MORNING_TEMP_FILE_PREFIX""brew_tap"
  brew tap > "$brew_tap_file"
  for tap in "${notaps[@]}"; do
    if grep -qE "^$tap$" "$brew_tap_file"; then
      brew untap "$tap"
    fi
  done
  taps=(
    homebrew/cask-fonts
    homebrew/cask-versions
    homebrew/services
    wata727/tflint # tflint - https://github.com/wata727/tflint#homebrew
  )
  for tap in "${taps[@]}"; do
    if ! grep -qE "^$tap$" "$brew_tap_file"; then
      brew tap "$tap"
    fi
  done
  rm -f "$brew_tap_file"
}

# Install homebrew - https://brew.sh
if ! type brew &> /dev/null; then
  eccho "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
else
  eccho "Updating Homebrew..."
  checkBrewTaps
  brew update 2> /dev/null
  eccho "Checking for outdated Homebrew formulas..."
  if [[ -n "$(brew upgrade)" ]]; then
    BREW_CLEANUP_NEEDED=1
    # If there was any output from the cleanup task, assume a formula changed or was installed.
    # Homebrew Doctor can take a long time to run, so now running only after formula changes...
    eccho "Running Hombrew Doctor since Homebrew updates were installed..."
    brew doctor
  fi
  eccho "Checking for outdated Homebrew Casks..."
  for outdatedCask in $(brew outdated --cask | sed -E 's/^([^ ]*) .*$/\1/'); do
    eccho "Upgrading $outdatedCask..."
    brew reinstall "$outdatedCask"
    BREW_CLEANUP_NEEDED=1
  done
fi

# Homebrew cask depends_on fix from: https://github.com/Homebrew/homebrew-cask/issues/58046
# The wireshark 3.0.0 install was the first cask that started to fail to update, but now succeeds
# with the following fix applied.
if [[ "$(getConfigValue 'applied_cask_depends_on_fix')" != "yes" ]]; then
  eccho "Applying the Homebrew depends_on metadata fix from https://github.com/Homebrew/homebrew-cask/issues/58046..."
  /usr/bin/find "$(brew --prefix)/Caskroom/"*'/.metadata' -type f -name '*.rb' -print0 | /usr/bin/xargs -0 /usr/bin/perl -i -0pe 's/depends_on macos: \[.*?\]//gsm;s/depends_on macos: .*//g'
  setConfigValue "applied_cask_depends_on_fix" "yes"
fi

# Homebrew casks
casks=(
  # android-platform-tools # uncomment if you need Android dev tools
  # android-studio # uncomment if you need Android dev tools
  # beyond-compare
  brave-browser
  charles
  # controlplane # mac automation based on hardware events
  # cord # remote desktop into windows machines from macOS
  # dash # https://kapeli.com/dash
  # dbeaver-community
  # discord
  docker
  # docker-edge
  # dropbox   dropbox.com returns 403 on install
  # etcher # Flash OS images to SD cards & USB drives, safely and easily.
  # firefox
  font-fira-code
  # google-backup-and-sync
  # google-chrome
  gpg-suite
  handbrake
  iterm2
  keeweb
  # keybase
  keyboard-maestro # keyboard macros
  # logitech-gaming-software # if you plug-in a logitech keyboard
  # microsoft-office
  # microsoft-teams
  # omnifocus
  # omnigraffle
  # onedrive
  # openconnect-gui # connect to a Cisco Connect VPN
  # opera
  # parallels
  postman
  provisionql # quick-look for iOS provisioning profiles
  # qladdict # Need to check all these quick-look extensions for Big Sur compatibility.
  # qlcolorcode
  # qlmarkdown
  # qlstephen
  # quicklook-json
  rocket # utf-8 emoji quick lookup and insert in any macOS app
  # sketch
  skitch
  slack
  # sourcetree
  tableplus
  the-unarchiver
  transmission # open source BitTorrent client from https://github.com/transmission/transmission
  tunnelblick # connect to your VPN
  vanilla # hide menu icons on your mac
  visual-studio-code
  # visual-studio-code-insiders
  wireshark
  # xmind-zen
  # zoom
)
cask_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_list"
cask_collision_file="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_collision"
brew list --cask > "$cask_list_temp_file"

# Uninstall specific Homebrew casks that conflict with this script if installed.
problem_casks=(
  insomniax # remove since this is now unmaintained
  virtualbox # deprecated since Docker for Desktop already comes with hyperkit
  wavtap # deprecated
  zoomus # replaced with zoom
)
for cask in "${problem_casks[@]}"; do
  if grep -qE "(^| )$cask($| )" "$cask_list_temp_file"; then
    brew uninstall --cask --force "$cask"
  fi
done

# Install Homebrew casks
for cask in "${casks[@]}"; do
  if ! grep -qE "(^| )$cask($| )" "$cask_list_temp_file"; then
    eccho "Installing $cask with Homebrew..."
    brew install --cask "$cask" 2>&1 > /dev/null | grep "Error: It seems there is already an App at '.*'\." | sed -E "s/.*'(.*)'.*/\1/" > "$cask_collision_file"
    if [[ -s "$cask_collision_file" ]]; then
      # Remove non-brew installed version of app and retry.
      sudoit rm -rf "$(cat "$cask_collision_file")"
      rm -f "$cask_collision_file"
      brew install --cask "$cask"
    fi
    NEW_BREW_CASK_INSTALLS=1
    BREW_CLEANUP_NEEDED=1
  fi
done
rm -f "$cask_collision_file" "$cask_list_temp_file"
unset cask_collision_file
unset brewCasks

# Install Homebrew formulas
formula_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""formula_list"
function ensureFormulaListCache {
  if ! [[ -s "$formula_list_temp_file" ]]; then
    brew list --formula > "$formula_list_temp_file"
  fi
}

function changeFormula {
  local formula_name="$1"
  local brew_command="$2"
  local formula_ref="${3:-$formula_name}"
  ensureFormulaListCache
  if ! grep -qE "(^| )$formula_name($| )" "$formula_list_temp_file"; then
    # shellcheck disable=SC2046
    brew "$brew_command" "$formula_ref" \
      $(if [[ "$brew_command" == "uninstall" ]]; then echo "--force --ignore-dependencies"; fi)
  fi
}

function ensureFormulaInstalled {
  local formula_name="$1"
  local formula_ref="${2:-$formula_name}"
  changeFormula "$formula_name" install "$formula_ref"
}

function ensureFormulaUninstalled {
  local formula_name="$1"
  changeFormula "$formula_name" uninstall
}

# Uninstall formulas that create conflicts and may or may not have been
# previously installed by earlier versions of this script.
problem_formulas=(
  bash-completion
)
for formula in "${problem_formulas[@]}"; do
  ensureFormulaUninstalled "$formula"
done
unset problem_formulas

# shellcheck disable=SC2034
formulas=(
  # ansible
  # automake
  # azure-cli
  bash
  bash-completion@2
  brew-cask-completion
  caddy
  # cassandra
  certbot # For generating SSL certs with Let's Encrypt
  coreutils
  # dialog # https://invisible-island.net/dialog/
  deno
  direnv # https://direnv.net/
  docker-squash # https://github.com/goldmann/docker-squash
  fd # https://github.com/sharkdp/fd
  # fish
  fx # https://github.com/antonmedv/fx
  fzf # https://github.com/junegunn/fzf
  # gcc
  # gem-completion
  git
  git-lfs
  go
  # highlight
  httpie # https://github.com/jakubroztocil/httpie
  # isl
  jq
  # kops
  # kubernetes-cli
  # kubernetes-helm
  # launchctl-completion
  # lnav
  # maven
  # maven-completion
  # minikube
  # neovim
  nss # needed by caddy for certutil
  openssl@1.1
  openssl@3
  p7zip # provides 7z command
  # packer
  # packer-completion
  pandoc
  # pgcli
  # pgtune
  # pgweb
  pip-completion
  # pyenv
  python@3.12 # vim was failing load without this - 3/2/2018
  readline # for pyenv installs of python
  # redis
  shellcheck # shell script linting
  # swagger-codegen # requires brew install --cask homebrew/cask-versions/adoptopenjdk8
  terraform
  tflint
  tmux
  vegeta
  vim
  watchman
  wget
  xz # for pyenv installs of python
  zlib
  zsh
  zsh-completions
)
for formula in "${formulas[@]}"; do
  ensureFormulaInstalled "$formula"
done

unset formulas
rm -f "$formula_list_temp_file"
unset formula_list_temp_file

# sshpass is not for ssh novices. Leave this step disabled unless you understand the risks of it.
# ensureFormulaInstalled sshpass "https://raw.githubusercontent.com/kadwanev/bigboybrew/master/Library/Formula/sshpass.rb"

if [[ -n "$BREW_CLEANUP_NEEDED" ]]; then
  unset BREW_CLEANUP_NEEDED;
  eccho "Cleaning up Homebrew cache..."
  # The -s option clears even the latest versions of uninstalled formulas and casks.
  # This does not clear the cache of versions currently installed.
  brew cleanup -s
fi

# Run this to set your shell to use fish (user, not root)
# chsh -s `which fish`

# function checkPythonInstall {
#   local pythonVersion="$1"
#   if ! pyenv versions | grep -q "$pythonVersion"; then
#     SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
#     CFLAGS="-I$(brew --prefix openssl)/include -O2" \
#     LDFLAGS="-L$(brew --prefix openssl)/lib" \
#     pyenv install "$pythonVersion"
#   fi
# }

# function checkPythonVersions {
#   local python2version="2.7.17"
#   local python3version="3.8.1"
#   checkPythonInstall "$python2version"
#   checkPythonInstall "$python3version"
#   local globalPythonVersion
#   if [[ "$GOOD_MORNING_USE_LEGACY_PYTHON" == 1 ]]; then
#     globalPythonVersion="$python2version"
#   else
#     globalPythonVersion="$python3version"
#   fi
#   pyenv global "$globalPythonVersion"
# }
# checkPythonVersions

# function checkOhMyFish {
#   if ! type "omf" &> /dev/null; then
#     local temp_omf_install_file="$HOME/.good_morning_omf_install.temp"
#     curl -L https://get.oh-my.fish > "$temp_omf_install_file"
#     fish "$temp_omf_install_file" < /dev/tty
#     rm -f "$temp_omf_install_file"
#   else
#     omf update
#   fi
# }
# checkOhMyFish - Need to find a way to avoid it immediately entering fish
# and stopping the rest of the script. Might try creating a process fork for this.

function pickbin {
  local versions="$1"
  for version in $versions; do
    if type "$version" &> /dev/null; then
      echo "$version"
      return
    fi
  done
}

function findpip {
  pickbin 'pip pip3 pip3.9'
}

eccho "Checking pip install..."
localpip="$(findpip)"
if [[ "$localpip" != "pip" ]] || ! pip &> /dev/null; then
  eccho "Installing pip..."
  wget https://bootstrap.pypa.io/get-pip.py --output-document ~/get-pip.py
  python ~/get-pip.py --user
  rm -f ~/get-pip.py
else
  eccho "Checking for update to pip..."
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
  pip-review
  pipdeptree
  pipenv
  pycurl
  requests
  virtualenv
)
for pip in "${pips[@]}"; do
  if ! grep -qi "$pip==" "$piptempfile"; then
    SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
    CFLAGS="-I$(brew --prefix openssl)/include -O2" \
    LDFLAGS="-L$(brew --prefix openssl)/lib" \
    "$(findpip)" install "$pip"
  fi
done
unset pips
rm -f "$piptempfile"
unset piptempfile

if ! pip-review | grep -q "Everything up-to-date"; then
  eccho "Upgrading pip installed packages..."
  SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
  CFLAGS="-I$(brew --prefix openssl)/include -O2" \
  LDFLAGS="-L$(brew --prefix openssl)/lib" \
  pip-review --auto
  # temporary workaround until we can ignore upgrading deps beyond what is supported (i.e. awscli and prompt-toolkit)
  pip install "prompt-toolkit<1.1.0,>=1.0.0" > /dev/null # fix previous upgrades that went to 2.0
fi

function upgradeNPM {
  eccho "Checking Node.js $(node -v) global npm package versions..."
  # Upgrade all global packages other than npm to latest
  for package in $(npm --global outdated --parseable --depth=0 | cut -d: -f4); do
    eccho "Upgrading global package $package for Node.js $(node -v)..."
    npm install "$package" --global
  done
  if ! type "ncu" &> /dev/null; then
    eccho "Installing the npm-check-updates global package..."
    npm install npm-check-updates --global
  fi
  if ! type "lerna" &> /dev/null; then
    eccho "Installing the lerna global package..."
    npm install lerna --global
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
    eccho "Clearing Node Version Manager cache..."
    nvm cache clear > /dev/null
    if [[ "$active_version" == "$old_version" ]]; then
      # In this case, the version that was active will be uninstalled.
      # Track the new one as the active_version
      active_version="$new_version"
    fi
    local reinstall_version
    reinstall_version="$(if [[ \"$old_version\" == \"N/A\" ]]; then echo "$active_version"; else echo "$old_version"; fi)"
    if [[ "$reinstall_version" != "N/A" ]] && [[ "$reinstall_version" != "$new_version" ]]; then
      eccho "Installing global Node.js packages used by $reinstall_version into $new_version..."
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
  eccho "Loading Node Version Manager..."
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh" > /dev/null
  eccho "Getting Node.js version information..."
  # cached because calling nvm version-remote takes a noticeable amount of time
  nvm_local_node="$(nvm version node)"
  nvm_latest_node="$(nvm version-remote node)"
  nvm_local_lts="$(nvm version lts/*)"
  if [[ "$nvm_local_lts" == "N/A" ]]; then
    # no local lts installed, or local lts is no longer the latest lts
    local last_node_lts_installed
    last_node_lts_installed="$(getConfigValue 'last_node_lts_installed')"
    if [[ -n "$last_node_lts_installed" ]] && \
      nvm ls "$last_node_lts_installed" | grep -q "$last_node_lts_installed"
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
      eccho "Uninstalling Node.js $local_version..."
      nvm uninstall "$local_version"
  fi
}

if ! [[ -s "$HOME/.nvm/nvm.sh" ]] || ! nvm --version | grep -q "$nvm_version"; then
  if [[ -n "$NVM_DIR" ]]; then
    mkdir -p "$NVM_DIR" # ensure directory exists if environment variable is set by existing bash_profile
  fi
  # https://github.com/creationix/nvm#install-script
  eccho "Installing Node Version Manager v$nvm_version"
  curl -o- "https://raw.githubusercontent.com/creationix/nvm/v${nvm_version}/install.sh" | bash
  loadNVM
  eccho "Installing latest Node.js..."
  checkNodeVersion "$nvm_local_node" "$nvm_latest_node"
  eccho "Installing latest Node.js LTS..."
  checkNodeVersion "$nvm_local_lts" "$nvm_latest_lts"
  eccho "Setting default Node.js version to be the latest..."
  nvm alias default node
else
  loadNVM
  eccho "Checking version of installed Node.js..."
  checkNodeVersion "$nvm_local_node" "$nvm_latest_node"
  eccho "Checking version of installed Node.js LTS..."
  checkNodeVersion "$nvm_local_lts" "$nvm_latest_lts"
fi
setConfigValue "last_node_lts_installed" "$nvm_latest_lts"
unset nvm_version
unset nvm_local_node
unset nvm_latest_node
unset nvm_local_lts
unset nvm_latest_lts

if [[ -n "$FIRST_RUN" ]] && askto "review and install some recommended applications"; then
  eccho "Follow these steps to complete the iTerm setup:"
  eccho "1. In Preferences > Profiles > Colors and select Tango Dark from the Color Presets... drop down."
  eccho "2. In Prefernces > Profiles > Terminal, set the iTerm buffer scroll back to 100000."
  eccho "3. Run the Install Shell Integration command from the iTerm2 menu."
  eccho "4. Use iTerm instead of Terminal from now on. Learn more here: https://iterm2.com/"
  prompt "Hit Enter to continue..."
  # todo: insert directly into plist located here $HOME/Library/Preferences/com.googlecode.iterm2.plist
  # todo: change plist directly for scroll back Root > New Bookmarks > Item 0 > Unlimited Scrollback > Boolean YES

  # Ensure Atom Shell Commands are installed
  if [[ -d "/Applications/Atom.app" ]] && ! type "apm" > /dev/null; then
    eccho "You need to install the Atom shell commands from inside Atom."
    eccho "After Atom opens, go to the Atom menu and select Atom > Install Shell Commands."
    prompt "Hit Enter to open Atom..."
    open "/Applications/Atom.app"
    prompt "Select the menu item Atom > Install Shell Commands and hit Enter here when finished..."
    if ! apm list | grep -q "── vim-mode@" && askto "install Atom vim-mode"; then
      apm install vim-mode ex-mode
    fi
  fi
fi

if [[ -n "$FIRST_RUN" ]] && ! (defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled && \
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
  local linkPath
  linkPath="/Applications/Utilities/$(echo "$1" | sed -E "s/.*\/(.*\.app)/\1/")"
  if [[ -d "$1" ]] && ! [[ -L "$linkPath" ]]; then
    eccho "Creating $linkPath symlink..."
    sudoit ln -s "$1" "$linkPath"
  fi
}
linkUtil "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"

function approveAllApps {
  if xattr -v -- /Applications/* | grep -q "com.apple.quarantine"; then
    local apps
    eccho "Auto-approving applications for Gatekeeper..."
    # get list of apps that have the com.apple.quarantine extended attribute set and then remove the attribute
    IFS=$'\n'
    # shellcheck disable=SC2207
    apps=($(xattr -v -- /Applications/* | grep "com.apple.quarantine" | \
      sed -E 's/^(.*): com.apple.quarantine$/\1/'))
    unset IFS
    for app in "${apps[@]}"; do
      eccho "Approving $(echo "$app" | sed -E 's/\/Applications\/(.*)\.app/\1/')..."
      sudoit xattr -d com.apple.quarantine "$app"
    done
  fi
}

function reindexSpotlight {
  eccho "Triggering a rebuild of the Spotlight index to ensure all new brew casks appear..."
  sudoit mdutil -E /
}

if [[ -n "$NEW_BREW_CASK_INSTALLS" ]]; then
  unset NEW_BREW_CASK_INSTALLS
  # Moved this lower since it's not important to do this earlier in the script
  # and it might avoid prompting for the password until more of the work is done.
  reindexSpotlight
fi
approveAllApps
# Check permissions again since new installs and updates will often undo
# these important changes.
checkPerms

if (( FIRST_RUN == 1 )) || [[ -z "$GOOD_MORNING_RUN" ]] \
  && askto "set some opinionated starter system settings"; then

  eccho "Optimizing System Settings"
  eccho "Only show icons of running apps in app bar, using Spotlight to launch"
  defaults write com.apple.dock static-only -bool true
  eccho "Auto show and hide the menu bar"
  defaults write -g _HIHideMenuBar -bool false
  eccho "Attach the dock to the left side, the definitive optimal location according to the community"
  defaults write com.apple.dock orientation left
  eccho "Do not add recently used apps to the dock automatically."
  defaults write com.apple.dock show-recents -bool false
  eccho "Enable tap to click on trackpad"
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  eccho "Bump up the trackpad speed a couple notches"
  defaults write -g com.apple.trackpad.scaling 2
  eccho "Turn off the annoying auto-capitalize while typing"
  defaults write -g NSAutomaticCapitalizationEnabled -bool false
  eccho "Turn off dash substitution"
  defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
  eccho "Set beep volume to 0"
  defaults write -g com.apple.sound.beep.volume -int 0
  eccho "Turn off the cursor location assist that will grow the cursor size when shaken"
  defaults write -g CGDisableCursorLocationMagnification -bool true
  eccho "Bump the mouse scaling up a couple notches"
  defaults write -g com.apple.mouse.scaling -float 2
  eccho "Set interface style to dark"
  defaults write -g AppleInterfaceStyle -string "Dark"
  eccho "Set a short alert sound"
  defaults write -g com.apple.sound.beep.sound -string "/System/Library/Sounds/Pop.aiff"
  # todo: hide siri
  eccho "Set fast speed key repeat rate, setting to 0 basically deletes everything at"
  eccho "once in some slower apps. 1 is still too fast for some apps. 2 is the"
  eccho "reasonable safe min."
  defaults write -g KeyRepeat -int 2
  eccho "Set the delay until repeat to be very short"
  defaults write -g InitialKeyRepeat -int 15
  eccho "Disable the auto spelling correction since technical acronyms and names get so often miss-corrected"
  defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
  eccho "Show Volume in the menu bar"
  defaults write com.apple.systemuiserver menuExtras -array-add "/System/Library/CoreServices/Menu Extras/Volume.menu"
  defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.volume" -bool true
  eccho "Increase window resize speed for Cocoa applications"
  defaults write -g NSWindowResizeTime -float 0.001
  eccho "Expand save panel by default"
  defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
  eccho "Expand print panel by default"
  defaults write -g PMPrintingExpandedStateForPrint -bool true
  eccho "Save to disk (not to iCloud) by default"
  defaults write -g NSDocumentSaveNewDocumentsToCloud -bool false
  eccho "Automatically quit printer app once the print jobs complete"
  defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
  eccho "Disable the "Are you sure you want to open this application?" dialog"
  defaults write com.apple.LaunchServices LSQuarantine -bool false
  eccho "Display ASCII control characters using caret notation in standard text views"
  defaults write -g NSTextShowsControlCharacters -bool true
  eccho "Disable Resume system-wide"
  defaults write -g NSQuitAlwaysKeepsWindows -bool false
  eccho "Disable automatic termination of inactive apps"
  defaults write -g NSDisableAutomaticTermination -bool true
  eccho "Disable automatic period substitution as it’s annoying when typing code"
  defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
  eccho "Disable automatic quote substitution as it inevitably happens when writing JavaScript or JSON"
  defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
  eccho "Disable the crash reporter"
  defaults write com.apple.CrashReporter DialogType -string "none"
  eccho "Set Help Viewer windows to non-floating mode"
  defaults write com.apple.helpviewer DevMode -bool true
  eccho "Reveal IP address, hostname, OS version, etc. when clicking the clock in the login window"
  sudoit defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
  eccho "Check for software updates daily, not just once per week"
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

  eccho "Optimizing Mouse & Trackpad Settings"
  eccho "Enable tap to click for this user and for the login screen"
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.mouse.tapBehavior -int 1
  eccho "Map bottom right corner to right-click"
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
  defaults -currentHost write -g com.apple.trackpad.trackpadCornerClickBehavior -int 1
  defaults -currentHost write -g com.apple.trackpad.enableSecondaryClick -bool true
  eccho "Swipe between pages with three fingers"
  defaults write -g AppleEnableSwipeNavigateWithScrolls -bool true
  defaults -currentHost write -g com.apple.trackpad.threeFingerHorizSwipeGesture -int 1
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 1
  eccho "'Tap with three fingers' instead of 'Force click with one finger' for 'Look up' feature"
  defaults -currentHost write -g com.apple.trackpad.forceClick -int 0
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 2
  eccho "Use scroll gesture with the Ctrl (^) modifier key to zoom"
  defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
  defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144

  eccho "Optimizing Bluetooth Settings"
  eccho "Increase sound quality for Bluetooth headphones/headsets"
  defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

  eccho "Optimizing Keyboard Settings"
  eccho "Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)"
  defaults write -g AppleKeyboardUIMode -int 3
  eccho "Follow the keyboard focus while zoomed in"
  defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
  eccho "Disable press-and-hold for keys in favor of key repeat"
  defaults write -g ApplePressAndHoldEnabled -bool false
  eccho "Automatically illuminate built-in MacBook keyboard in low light"
  defaults write com.apple.BezelServices kDim -bool true
  eccho "Turn off keyboard illumination when computer is not used for 5 minutes"
  defaults write com.apple.BezelServices kDimTime -int 300
  eccho "Set language and text formats"
  defaults write -g AppleLanguages -array "en"
  defaults write -g AppleLocale -string "en_US@currency=USD"
  defaults write -g AppleMeasurementUnits -string "Inches"
  defaults write -g AppleMetricUnits -bool false
  eccho "Disable auto-correct"
  defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write -g WebAutomaticSpellingCorrectionEnabled -bool false
  eccho "Turn off typing suggestions in the touch bar"
  defaults write -g NSAutomaticTextCompletionEnabled -bool false

  eccho "Optimizing Screen Settings"
  eccho "Require password immediately after sleep or screen saver begins"
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
  eccho "Top right screen corner starts the screen saver instead of using idle time"
  defaults write com.apple.dock wvous-tr-corner -int 5
  defaults write com.apple.dock wvous-tr-modifier -int 0
  defaults -currentHost write com.apple.screensaver idleTime 0
  eccho "Save screenshots to the desktop"
  defaults write com.apple.screencapture location -string "$HOME/Desktop"
  eccho "Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)"
  defaults write com.apple.screencapture type -string "png"
  eccho "Disable shadow in screenshots"
  defaults write com.apple.screencapture disable-shadow -bool true
  eccho "Enable subpixel font rendering on non-Apple LCDs"
  defaults write -g AppleFontSmoothing -int 2
  eccho "Enable HiDPI display modes (requires restart)"
  sudoit defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  eccho "Optimizing Finder Settings"
  eccho "Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons"
  defaults write com.apple.finder QuitMenuItem -bool true
  eccho "Finder: disable window animations and Get Info animations"
  defaults write com.apple.finder DisableAllAnimations -bool true
  eccho "Show icons for hard drives, servers, and removable media on the desktop"
  defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
  defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
  eccho "Finder: show hidden files by default"
  defaults write com.apple.finder AppleShowAllFiles -bool true
  eccho "Finder: show path bar"
  defaults write com.apple.finder ShowPathbar -bool true
  eccho "Finder: show all filename extensions"
  defaults write -g AppleShowAllExtensions -bool true
  eccho "Finder: show status bar"
  defaults write com.apple.finder ShowStatusBar -bool true
  eccho "Finder: allow text selection in Quick Look"
  defaults write com.apple.finder QLEnableTextSelection -bool true
  eccho "Display full POSIX path as Finder window title"
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  eccho "When performing a search, search the current folder by default"
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  eccho "Disable the warning when changing a file extension"
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  eccho "Avoid creating .DS_Store files on network volumes"
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  eccho "Disable disk image verification"
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
  eccho "Automatically open a new Finder window when a volume is mounted"
  defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  eccho "Use list view in all Finder windows by default"
  # You can set the other view modes by using one of these four-letter codes: icnv, clmv, Flwv
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  eccho "Disable the warning before emptying the Trash"
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
  eccho "Empty Trash securely by default"
  defaults write com.apple.finder EmptyTrashSecurely -bool true
  eccho "Enable AirDrop over Ethernet and on unsupported Macs running Lion"
  defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true
  eccho "Display all file sizes in Finder windows"
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Delete "StandardViewSettings:ExtendedListViewSettings:calculateAllSizes" bool'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Add "StandardViewSettings:ExtendedListViewSettings:calculateAllSizes" bool true'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Delete "StandardViewSettings:ListViewSettings:calculateAllSizes" bool'
  /usr/libexec/PlistBuddy "$HOME/Library/Preferences/com.apple.finder.plist" -c 'Add "StandardViewSettings:ListViewSettings:calculateAllSizes" bool true'
  eccho "Turn off Finder sounds"
  defaults write com.apple.finder 'FinderSounds' -bool false
  eccho "Making ~/Library visible"
  /usr/bin/chflags nohidden "$HOME/Library"
  eccho "Disabling '<App> is an application downloaded from the internet. Are you sure you want to open it?"
  defaults write com.apple.LaunchServices LSQuarantine -bool false

  eccho "Optimizing Dock Settings"
  eccho "Enable highlight hover effect for the grid view of a stack (Dock)"
  defaults write com.apple.dock mouse-over-hilte-stack -bool true
  eccho "Set the icon size of Dock items to 36 pixels"
  defaults write com.apple.dock tilesize -int 36
  eccho "Enable spring loading for all Dock items"
  defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
  eccho "Show indicator lights for open applications in the Dock"
  defaults write com.apple.dock show-process-indicators -bool true
  eccho "Don’t animate opening applications from the Dock"
  defaults write com.apple.dock launchanim -bool false
  eccho "Speed up Mission Control animations"
  defaults write com.apple.dock expose-animation-duration -float 0.1
  eccho "Remove the auto-hiding Dock delay"
  defaults write com.apple.Dock autohide-delay -float 0
  eccho "Remove the animation when hiding/showing the Dock"
  defaults write com.apple.dock autohide-time-modifier -float 0
  eccho "Automatically hide and show the Dock"
  defaults write com.apple.dock autohide -bool true
  eccho "Make Dock icons of hidden applications translucent"
  defaults write com.apple.dock showhidden -bool true

  eccho "Optimizing Safari & WebKit Settings"
  eccho "Set Safari’s home page to about:blank for faster loading"
  defaults write com.apple.Safari HomePage -string "about:blank"
  eccho "Prevent Safari from opening ‘safe’ files automatically after downloading"
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
  eccho "Hide Safari’s bookmarks bar by default"
  defaults write com.apple.Safari ShowFavoritesBar -bool false
  eccho "Disable Safari’s thumbnail cache for History and Top Sites"
  defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
  eccho "Enable Safari’s debug menu"
  defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
  eccho "Make Safari’s search banners default to Contains instead of Starts With"
  defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
  eccho "Remove useless icons from Safari’s bookmarks bar"
  defaults write com.apple.Safari ProxiesInBookmarksBar ""
  eccho "Enable the Develop menu and the Web Inspector in Safari"
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  eccho "Add a context menu item for showing the Web Inspector in web views"
  defaults write -g WebKitDeveloperExtras -bool true
  eccho "Enable the WebKit Developer Tools in the Mac App Store"
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true

  eccho "Optimizing iTunes Settings"
  eccho "Disable the iTunes store link arrows"
  defaults write com.apple.iTunes show-store-link-arrows -bool false
  eccho "Disable the Genius sidebar in iTunes"
  defaults write com.apple.iTunes disableGeniusSidebar -bool true
  eccho "Disable the Ping sidebar in iTunes"
  defaults write com.apple.iTunes disablePingSidebar -bool true
  eccho "Disable all the other Ping stuff in iTunes"
  defaults write com.apple.iTunes disablePing -bool true
  eccho "Disable radio stations in iTunes"
  defaults write com.apple.iTunes disableRadio -bool true
  eccho "Make ⌘ + F focus the search input in iTunes"
  defaults write com.apple.iTunes NSUserKeyEquivalents -dict-add "Target Search Field" "@F"

  eccho "Optimizing Mail Settings"
  eccho "Disable send and reply animations in Mail.app"
  defaults write com.apple.mail DisableReplyAnimations -bool true
  defaults write com.apple.mail DisableSendAnimations -bool true
  eccho "Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app"
  defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@U21a9"

  eccho "Optimizing Terminal Settings"
  eccho "Enable \"focus follows mouse\" for Terminal.app and all X11 apps."
  eccho "i.e. hover over a window and start typing in it without clicking first"
  defaults write com.apple.terminal FocusFollowsMouse -bool true
  defaults write org.x.X11 wm_ffm -bool true

  eccho "Optimizing Time Machine Settings"
  eccho "Prevent Time Machine from prompting to use new hard drives as backup volume"
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  eccho "Optimizing Address Book, Dashboard, iCal, TextEdit, and Disk Utility Settings"
  eccho "Enable the debug menu in Address Book"
  defaults write com.apple.addressbook ABShowDebugMenu -bool true
  eccho "Enable Dashboard dev mode (allows keeping widgets on the desktop)"
  defaults write com.apple.dashboard devmode -bool true
  eccho "Use plain text mode for new TextEdit documents"
  defaults write com.apple.TextEdit RichText -int 0
  eccho "Open and save files as UTF–8 in TextEdit"
  defaults write com.apple.TextEdit PlainTextEncoding -int 4
  defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
  eccho "Enable the debug menu in Disk Utility"
  defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
  defaults write com.apple.DiskUtility advanced-image-options -bool true

  eccho "Optimizing Energy Settings"
  eccho "Stay on for 60 minutes with battery and 3 hours when plugged in"
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict "Display Sleep Timer" -int 60
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict "System Sleep Timer" -int 60
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "AC Power" -dict "System Sleep Timer" -int 180
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "AC Power" -dict "Display Sleep Timer" -int 180
  eccho "Show battery percentage"
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"
  eccho "Turn off the boot sound effect"
  sudoit nvram SystemAudioVolume=" "

  eccho "Restart your computer to see all the changes."
fi

if [[ -z "$GOOD_MORNING_RUN" ]]; then
  eccho "Use the command good-morning each day to stay up-to-date!"
fi

function cleanupTempFiles {
  local good_morning_pass_file_temp="$HOME/.good_morning_pass_file" # lacks 'temp' in name to bypass deletion if kept
  # Clean-up the encrypted pass file used for sudo calls unless disabled by the config.
  if [[ "$(getConfigValue 'keep_pass_for_session')" == "yes" ]] && [[ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]]; then
    mv "$GOOD_MORNING_ENCRYPTED_PASS_FILE" "$good_morning_pass_file_temp"
  fi
  # A glob file deletion is about to happen, proceed with excessive caution.
  if [[ "$GOOD_MORNING_TEMP_FILE_PREFIX" == "$HOME/.good_morning_temp_" ]]; then
    rm -f "$GOOD_MORNING_TEMP_FILE_PREFIX"*
  else
    errcho "Warning: Unexpected pass file prefix. Temp file clean-up is incomplete."
  fi
  # Move the encrypted pass file back post cleanup if deleting it was disabled by the config.
  if [[ "$(getConfigValue 'keep_pass_for_session')" == "yes" ]] && [[ -e "$good_morning_pass_file_temp" ]]; then
    mv "$good_morning_pass_file_temp" "$GOOD_MORNING_ENCRYPTED_PASS_FILE"
  fi
}

function cleanupEnvVars {
  unset FIRST_RUN
  unset GIT_EMAIL
  unset GITHUB_KEYS_URL
  unset GIT_NAME
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
  if [[ -n "$GOOD_MORNING_RUN" ]]; then
    unset GOOD_MORNING_RUN
    local keep_pass_for_session
    keep_pass_for_session="$(getConfigValue 'keep_pass_for_session' 'not-asked')"
    if [[ -z "$keep_pass_for_session" || "$keep_pass_for_session" == "not-asked" ]] \
      && [[ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]]; then

      if askto "always be prompted for your password if needed when you run good-morning again in the same session"; then
        setConfigValue "keep_pass_for_session" "no"
      else
        setConfigValue "keep_pass_for_session" "yes"
      fi
    fi
    cleanupTempFiles
    cleanupEnvVars
  else
    eccho "Almost done! Pulling latest for good-morning repository..."
    cleanupTempFiles
    pushd "$GOOD_MORNING_REPO_ROOT" > /dev/null
    cleanupEnvVars && git pull && popd > /dev/null
  fi
}
cleanupGoodMorning

function greeting {
  local hour
  hour=$(date "+%k")
  if (( hour < 12 )); then
    eccho "Done. Good morning!"
  elif (( hour < 18 )); then
    eccho "Done. Good afternoon!"
  else
    eccho "Done. Good evening!"
  fi
}
greeting
