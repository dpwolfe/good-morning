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

# Persistent log of every run. The script is normally sourced into the user's interactive shell (see the
# `good-morning` alias in dotfiles/.bash_profile), which means a hard exit closes their terminal window and loses
# scrollback. Tee everything to a timestamped log file so there is always something to inspect after the fact,
# regardless of how the run ended.
GOOD_MORNING_LOG_DIR="$HOME/.good-morning-logs"
GOOD_MORNING_LOG_FILE="$GOOD_MORNING_LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"
GM_LOGGING_ACTIVE=
if mkdir -p "$GOOD_MORNING_LOG_DIR" 2> /dev/null; then
  exec 7>&1 8>&2
  # Tee to terminal (raw, with color) AND to the log file (ANSI-stripped via perl). macOS BSD `sed` cannot match
  # \e/\x1b in regex, so use perl which handles both CSI sequences (\e[...m, \e[...K, etc.) and the SGR-followup G0
  # charset designator (\e(B) that bash emits after colored output. `BEGIN{$|=1}` disables perl's block buffering so
  # the file stays current in real time -- otherwise an aborted run could lose its tail.
  exec > >(tee >(perl -pe 'BEGIN{$|=1} s/\e\[[0-9;?]*[A-Za-z]//g; s/\e\([AB012]//g' \
    >> "$GOOD_MORNING_LOG_FILE")) 2>&1
  ln -sfn "$GOOD_MORNING_LOG_FILE" "$GOOD_MORNING_LOG_DIR/latest.log"
  GM_LOGGING_ACTIVE=1
  eccho "Logging this run to $GOOD_MORNING_LOG_FILE"
fi

# Restore the user's original stdout/stderr. Essential when sourced into an interactive shell.
function gm_restore_stdio {
  if [[ -n "$GM_LOGGING_ACTIVE" ]]; then
    exec 1>&7 2>&8
    exec 7>&- 8>&-
    GM_LOGGING_ACTIVE=
  fi
}

# Drop sudo session secrets on abort/interrupt. Happy path respects keep_pass_for_session.
function gm_scrub_sudo_secrets {
  if [[ -n "$GOOD_MORNING_ENCRYPTED_PASS_FILE" && -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]]; then
    rm -f "$GOOD_MORNING_ENCRYPTED_PASS_FILE"
  fi
  if [[ -n "$GOOD_MORNING_TEMP_FILE_PREFIX" && "$GOOD_MORNING_TEMP_FILE_PREFIX" == "$HOME/.good_morning_temp_" ]]; then
    rm -f "$GOOD_MORNING_TEMP_FILE_PREFIX"*
  fi
  unset GOOD_MORNING_ENCRYPTED_PASS_FILE
  unset GOOD_MORNING_PASSPHRASE
}

# Clear this run's traps so they do not stick on a sourced interactive shell.
function gm_clear_run_traps {
  trap - EXIT INT TERM
}

# Abort: scrub secrets, restore stdio, clear traps.
function gm_abort_prep {
  gm_scrub_sudo_secrets
  # Drop pip environment variables that may have been set
  unset PIP_BREAK_SYSTEM_PACKAGES
  unset PYCURL_SSL_LIBRARY
  errcho "good-morning aborted. Full log: $GOOD_MORNING_LOG_FILE"
  gm_restore_stdio
  gm_clear_run_traps
}

# EXIT only restores stdio. Do not scrub secrets here or keep_pass_for_session breaks.
function gm_on_exit {
  gm_restore_stdio
}

# INT/TERM while sourced: restore the shell and stop. return must be in the trap action itself.
trap 'gm_on_exit' EXIT
trap 'gm_abort_prep; return 130' INT TERM

function randstring32 {
  env LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1
}

if [[ -z "$GOOD_MORNING_PASSPHRASE" ]]; then
  GOOD_MORNING_PASSPHRASE="$(randstring32)"
fi
# export required for openssl -pass env: (incl. keep_pass value from a prior sourced run)
export GOOD_MORNING_PASSPHRASE
# Passphrase via env (not -k) so it stays out of ps. chmod 600 against a loose umask.
function encryptToFile {
  if ! printf '%s\n' "$1" | openssl enc -aes-256-cbc -pbkdf2 -pass env:GOOD_MORNING_PASSPHRASE > "$2"; then
    rm -f "$2"
    return 1
  fi
  chmod 600 "$2"
}

function decryptFromFile {
  openssl enc -aes-256-cbc -pbkdf2 -d -pass env:GOOD_MORNING_PASSPHRASE < "$1"
}

function askto {
  eccho "Do you want to $1? $3"
  read -r -n 1 -p "(Y/n) " yn < /dev/tty;
  echo # echo newline after input
  # shellcheck disable=SC2091
  # Enter = Yes. Still run $2 when provided (empty case used to return without eval).
  case $yn in
    y|Y|"")
      if [[ -n "$2" ]]; then
        eval "$2"
      fi
      return 0
      ;;
    n|N) return 1;;
    *) return 1;;
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
  # Write the prompt directly to /dev/tty rather than relying on `read -p`, which prints to stderr. Some callers
  # (e.g. the silent `2> /dev/null` loop in approveAllApps) redirect stderr, which would otherwise hide the prompt and
  # make the script look hung while it actually waits on /dev/tty input.
  printf '%s: ' "$1" > /dev/tty
  read -r -s "$2" < /dev/tty
  printf '\n' > /dev/tty
}

GOOD_MORNING_CONFIG_FILE="$HOME/.good_morning"
function getConfigValue {
  local val
  val="$( (grep -E "^$1=" -m 1 "$GOOD_MORNING_CONFIG_FILE" 2> /dev/null || echo "$1=$2") | head -n 1 | cut -d '=' -f 2-)"
  printf -- "%s" "$val"
}

function setConfigValue {
    # macOS uses Bash 3.x which does not support associative arrays yet; faking it is not worth the added complexity.
  local keep_pass_for_session
  keep_pass_for_session="$(getConfigValue "keep_pass_for_session" "not-asked")" # "not-asked", "no" or "yes"
  local applied_cask_depends_on_fix
  applied_cask_depends_on_fix="$(getConfigValue "applied_cask_depends_on_fix" "no")" # "no" or "yes"
  local last_node_lts_installed
  last_node_lts_installed="$(getConfigValue "last_node_lts_installed")"
  local spotlight_exclusions_hash
  spotlight_exclusions_hash="$(getConfigValue "spotlight_exclusions_hash")" # sha256 of the last reconciled exclusion set
  local tempfile="$GOOD_MORNING_CONFIG_FILE""_temp"
  # crude validation
  if [[ "$1" == "keep_pass_for_session" ]] || \
    [[ "$1" == "applied_cask_depends_on_fix" ]] || \
    [[ "$1" == "last_node_lts_installed" ]] || \
    [[ "$1" == "spotlight_exclusions_hash" ]]
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
    echo "spotlight_exclusions_hash=$spotlight_exclusions_hash";
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
  if ! [[ -e "$GOOD_MORNING_ENCRYPTED_PASS_FILE" ]] || ! decryptFromFile "$GOOD_MORNING_ENCRYPTED_PASS_FILE" 2> /dev/null | sudo -S -p "" printf ""; then
    GOOD_MORNING_ENCRYPTED_PASS_FILE="$GOOD_MORNING_TEMP_FILE_PREFIX$(randstring32)"
    local p=
    while [[ -z "$p" ]] || ! echo "$p" | sudo -S -p "" printf ""; do
      promptsecret "Password" p
    done
    if ! encryptToFile "$p" "$GOOD_MORNING_ENCRYPTED_PASS_FILE"; then
      errcho "Failed to cache sudo password for this run."
      unset p
      return 1
    fi
    unset p
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

# Minimum supported macOS version. Bump when a new macOS major ships and this script has been validated on it.
# Anything older is rejected with a hint. Apple switched to calendar-aligned numbering in 2025 (macOS 15 Sequoia ->
# macOS 26 Tahoe), so versions are compared as-is via `sort -V`.
GOOD_MORNING_MIN_MACOS_VERSION="26.0"

function getOSVersion {
  /usr/bin/sw_vers -productVersion
}

function checkOSRequirement {
  local current
  current="$(getOSVersion)"
  if [[ -z "$current" ]]; then
    errcho "Could not determine macOS version (sw_vers failed)."
    return 1
  fi
  # sort -V puts the lower version first; if min is the lower (or equal), the current version meets the minimum.
  local lowest
  lowest="$(printf '%s\n%s\n' "$GOOD_MORNING_MIN_MACOS_VERSION" "$current" | sort -V | head -n 1)"
  if [[ "$lowest" != "$GOOD_MORNING_MIN_MACOS_VERSION" ]]; then
    errcho "Good Morning requires macOS $GOOD_MORNING_MIN_MACOS_VERSION or newer (detected $current)."
    errcho "Upgrade macOS via System Settings > General > Software Update and run again."
    return 1
  fi
}

function checkPerms {
  eccho "Checking directory permissions..."
  # shellcheck disable=SC2207
  local dirs=(
    # Block of dirs that Homebrew needs the user to own for successful operation.
    # The redundancy of nested dirs is left here intentionally even though we use -R.
    # Intel Homebrew
    /usr/local/bin
    /usr/local/Caskroom
    /usr/local/Cellar
    /usr/local/etc
    /usr/local/Frameworks
    /usr/local/Homebrew
    /usr/local/include
    /usr/local/lib
    /usr/local/lib/pkgconfig
    /usr/local/opt
    /usr/local/sbin
    /usr/local/share
    /usr/local/share/locale
    /usr/local/share/man/*
    /usr/local/var
    /usr/local/var/homebrew
    # Apple Silicon Homebrew
    /opt/homebrew
    /opt/homebrew/bin
    /opt/homebrew/Caskroom
    /opt/homebrew/Cellar
    /opt/homebrew/etc
    /opt/homebrew/Frameworks
    /opt/homebrew/include
    /opt/homebrew/lib
    /opt/homebrew/lib/pkgconfig
    /opt/homebrew/opt
    /opt/homebrew/sbin
    /opt/homebrew/share
    /opt/homebrew/share/locale
    /opt/homebrew/share/man/*
    /opt/homebrew/var
    /opt/homebrew/var/homebrew
    # Needed for pip installs without requiring sudo
    /Library/Ruby/Gems/*
    /Library/Ruby/Site/*
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
}
checkOSRequirement || { gm_abort_prep; return 1 2> /dev/null || exit 1; }
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
eccho "Checking for Xcode Command Line Tools..."
if ! /usr/bin/xcode-select -p &> /dev/null \
    || ! [[ -d "$(/usr/bin/xcode-select -p 2> /dev/null)" ]]; then
  # Use Apple's xcode-select to trigger the GUI installer for Command Line Tools.
  eccho "Installing Xcode Command Line Tools (a GUI prompt will appear)..."
  /usr/bin/xcode-select --install &> /dev/null || true
  eccho "Waiting for Command Line Tools install to finish..."
  eccho "Dismissing the installer without finishing will time out. Ctrl+C aborts sooner. Re-run after install."
  # Cap at 60 minutes. Unbounded wait hung forever if the GUI was dismissed.
  gm_clt_wait_secs=0
  gm_clt_wait_limit=3600
  until /usr/bin/xcode-select -p &> /dev/null \
      && [[ -d "$(/usr/bin/xcode-select -p 2> /dev/null)" ]]; do
    if (( gm_clt_wait_secs >= gm_clt_wait_limit )); then
      errcho "Timed out waiting for Command Line Tools after $((gm_clt_wait_limit / 60)) minutes."
      errcho "Finish the installer (or run: xcode-select --install), then re-run good-morning."
      unset gm_clt_wait_secs gm_clt_wait_limit
      gm_abort_prep
      return 1 2> /dev/null || exit 1
    fi
    sleep 5
    gm_clt_wait_secs=$((gm_clt_wait_secs + 5))
  done
  unset gm_clt_wait_secs gm_clt_wait_limit
  eccho "Xcode Command Line Tools installed."
fi

function getLocalXcodeVersion {
  /usr/bin/xcodebuild -version 2>&1 | grep "Xcode" | sed -E 's/Xcode ([0-9|.]*)/\1/'
}

function getLocalXcodeBuildVersion {
  /usr/bin/xcodebuild -version 2>&1 | grep "Build" | sed -E 's/Build version ([0-9A-Za-z]+)/\1/'
}

# Full Xcode installs are user-driven via the Mac App Store.
# Command Line Tools are handled by xcode-select --install
function checkXcodeVersion {
  eccho "Checking Xcode developer directory..."
  local dev_path=""
  if /usr/bin/xcode-select --print-path &> /dev/null; then
    dev_path="$(/usr/bin/xcode-select --print-path)"
  fi
  if [[ -z "$dev_path" ]] || ! [[ -d "$dev_path" ]]; then
    errcho "No Xcode developer directory is set. Re-run after Command Line Tools install completes."
    return
  fi
  if [[ -d "/Applications/Xcode.app" ]]; then
    local xcode_dev_path="/Applications/Xcode.app/Contents/Developer"
    if [[ "$dev_path" != "$xcode_dev_path" ]]; then
      eccho "Switching xcode-select to /Applications/Xcode.app..."
      sudoit /usr/bin/xcode-select --switch "$xcode_dev_path"
    fi
    eccho "Xcode $(getLocalXcodeVersion) (Build $(getLocalXcodeBuildVersion)) is active."
  else
    eccho "Full Xcode.app is not installed; Command Line Tools at $dev_path will be used."
  fi
}
checkXcodeVersion

if [[ -d "/Applications/Xcode.app" ]] && /usr/bin/xcrun clang 2>&1 | grep -q "license"; then
  eccho "Accepting the Xcode license..."
  sudoit xcodebuild -license accept
  eccho "Installing Xcode packages..."
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDevice.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/MobileDeviceDevelopment.pkg -target /
  sudoit installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
fi

# Apple's CLT clang on macOS Tahoe (CLT 21.x) does not auto-discover the SDK, so anything that shells out to clang
# during a build (ruby-build, gem install native extensions via mkmf, pip C extensions) fails with either `fatal error:
# 'stdio.h' file not found` or `ld: library 'System' not found`. Setting SDKROOT once at the top of the script makes
# every child process inherit the right sysroot. xcrun resolves the active SDK whether the user has full Xcode or just
# Command Line Tools.
SDKROOT_RESOLVED="$(/usr/bin/xcrun --show-sdk-path 2> /dev/null)"
if [[ -n "$SDKROOT_RESOLVED" ]]; then
  export SDKROOT="$SDKROOT_RESOLVED"
fi
unset SDKROOT_RESOLVED

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
# Shared by SSH and GPG setup (GPG-only first runs used to open an empty URL).
GITHUB_KEYS_URL="https://github.com/settings/keys"
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
  ssh-add --apple-use-keychain "$HOME/.ssh/id_rsa"
  if askto "add your SSH key to GitHub or other source control provider"; then
    # copy public ssh key to clipboard for pasting on GitHub
    pbcopy < "$HOME/.ssh/id_rsa.pub"
    eccho "The public key is now in your clipboard."
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

# Decide up-front whether to offer GPG signing setup. Defer the actual key creation prompt until after Homebrew
# installs the gpg-suite cask.
gpg_setup_wanted=
if ! [[ -d "/Applications/GPG Keychain.app" ]] \
    && [[ -z "$(git config --global --get user.signingkey 2> /dev/null)" ]] \
    && askto "set up GPG signing for git commits (installs GPG Suite via Homebrew)"; then
  gpg_setup_wanted=1
fi

# Track the current Ruby stable line; bump as new patch versions ship.
# https://www.ruby-lang.org/en/downloads/releases/
latest_ruby_version="3.4.9"

function migrateFromRVM {
  [[ -d "$HOME/.rvm" ]] || return
  eccho "Detected legacy RVM install at \$HOME/.rvm. good-morning now uses rbenv."
  eccho "RVM is harmless when left dormant but adds shell startup overhead."
  eccho "To remove it cleanly when you're ready:"
  eccho "  rvm implode"
  eccho "  rm -f \$HOME/.rvmrc \$HOME/.profile  # if RVM-only"
  eccho "  Then remove this line from ~/.bash_profile:"
  eccho "    [ -s \"\$HOME/.profile\" ] && source \"\$HOME/.profile\""
}

function checkRbenvRuby {
  # Bootstrap Homebrew on first-run since rbenv installs via brew.
  if ! type brew &> /dev/null; then
    eccho "Installing Homebrew (required for rbenv)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  if ! type rbenv &> /dev/null; then
    eccho "Installing rbenv + ruby-build..."
    brew install --quiet rbenv ruby-build
  fi
  # Initialize rbenv into the current script shell so `rbenv install/global`
  # and `gem` invocations immediately see the right ruby.
  eval "$(rbenv init - bash)"
  # RVM's shell hooks (sourced from ~/.profile in legacy bash_profiles) export GEM_HOME/GEM_PATH pointing at
  # ~/.rvm/gems/<old-ruby>. If we leave those set, `gem update` and `gem install` resolve rbenv's ruby binary but write
  # to and iterate over RVM's gemset, then try to rebuild RVM-installed native extensions against the new Ruby's ABI
  # producing hundreds of mkmf errors. Strip every RVM-injected variable so all gem ops resolve via the rbenv ruby's
  # own site config. Becomes a no-op once the user `rvm implode`s.
  unset GEM_HOME GEM_PATH MY_RUBY_HOME IRBRC \
    rvm_bin_path rvm_path rvm_prefix rvm_version rvm_ruby_string
  if ! rbenv versions --bare 2> /dev/null | grep -qx "$latest_ruby_version"; then
    eccho "Installing Ruby $latest_ruby_version via rbenv..."
    # SDKROOT is exported globally near the top of the script so ruby-build's ./configure can find libSystem on Tahoe
    # with the CLT-only clang.
    rbenv install -s "$latest_ruby_version"
    # ruby-build leaves the build dir on failure but exits non-zero; either way, verify by asking rbenv directly.
    # Surface the build log path on failure so the user has something to read.
    if ! rbenv versions --bare 2> /dev/null | grep -qx "$latest_ruby_version"; then
      errcho "rbenv install $latest_ruby_version did not produce a working Ruby."
      local build_log
      build_log="$(/bin/ls -1t /var/folders/*/T/ruby-build.*.log 2> /dev/null | head -n 1)"
      [[ -n "$build_log" ]] && errcho "ruby-build log: $build_log"
      errcho "To retry with verbose output:"
      errcho "  SDKROOT=\"\$(xcrun --show-sdk-path)\" rbenv install --verbose $latest_ruby_version"
      return 1
    fi
  fi
  if [[ "$(rbenv global 2> /dev/null)" != "$latest_ruby_version" ]]; then
    eccho "Setting rbenv global Ruby to $latest_ruby_version..."
    rbenv global "$latest_ruby_version"
  fi
  rbenv rehash
}

migrateFromRVM
checkRbenvRuby || { gm_abort_prep; return 1 2> /dev/null || exit 1; }
updateGems

function installGems {
  local gem_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""gem_list"
  local gems=(
    cocoapods
    sqlint
    terraform_landscape
  )
  gem list --local > "$gem_list_temp_file"
  for gem in "${gems[@]}"; do
    if ! grep -q "$gem" "$gem_list_temp_file"; then
      eccho "Installing $gem..."
      gem install "$gem" --no-document
    fi
  done
  rm -f "$gem_list_temp_file"
  gem cleanup
  # Make any gem-installed binaries (cocoapods, etc.) immediately available via rbenv's shim layer.
  type rbenv &> /dev/null && rbenv rehash
}
installGems

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
  if [[ -s "$HOME/.bash_profile" ]]; then
    eccho "Renaming previous ~/.bash_profile to ~/.old_bash_profile..."
    mv "$HOME/.bash_profile" "$HOME/.old_bash_profile_$(date +%Y%m%d%H%M%S)"
  fi
  echo "export REPO_ROOT=\"\$HOME/repo\"
# Apple Silicon installs Homebrew at /opt/homebrew; Intel at /usr/local.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval \"\$(/opt/homebrew/bin/brew shellenv)\"
elif [[ -x /usr/local/bin/brew ]]; then
  eval \"\$(/usr/local/bin/brew shellenv)\"
fi
source \"\$REPO_ROOT/good-morning/dotfiles/.bash_profile\"
if ! contains \$(pwd) \"\$REPO_ROOT\"; then cd \"\$REPO_ROOT\"; fi
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"  # load nvm
[ -s \"\$NVM_DIR/bash_completion\" ] && \. \"\$NVM_DIR/bash_completion\"  # load nvm bash_completion
if command -v pyenv 1> /dev/null 2>&1; then eval \"\$(pyenv init -)\"; fi
if command -v rbenv 1> /dev/null 2>&1; then eval \"\$(rbenv init - bash)\"; fi
[ -s \"\$HOME/.iterm2_shell_integration.bash\" ] && source \"\$HOME/.iterm2_shell_integration.bash\"
" > "$HOME/.bash_profile"

  # copy some starter shell dot files
  cp "$GOOD_MORNING_REPO_ROOT/dotfiles/.inputrc" "$HOME/.inputrc"
  cp "$GOOD_MORNING_REPO_ROOT/dotfiles/.vimrc" "$HOME/.vimrc"
  cp -rf "$GOOD_MORNING_REPO_ROOT/dotfiles/.vim" "$HOME/.vim"
  # set flag to indicate this is the first run to turn on additional setup features
  FIRST_RUN=1
fi

# Auto-recover from two common post-`brew upgrade` states surfaced by `brew doctor`:
#   1. "You have unlinked kegs" - The new keg was poured but a conflicting file blocked `brew link`.
#      We force-link with --overwrite so the new version actually takes effect.
#   2. "Some installed kegs have no formulae" - A previously-tapped formula source is gone, leaving an orphaned keg
#      that brew can never upgrade. We defensively uninstall it, but if it's still wanted, the formulas[] install
#      loop will reinstall it from currently tapped sources.
function fixBrewDoctorIssues {
  local doctor unlinked orphaned formula
  doctor="$(brew doctor 2>&1)"
  unlinked="$(awk '
    /^Warning: You have unlinked kegs in your Cellar/ {flag=1; next}
    flag && /^Warning:/ {flag=0}
    flag && /^  [A-Za-z0-9_@.+-]+$/ {sub(/^ +/, ""); print}' <<< "$doctor")"
  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue
    eccho "Force-linking unlinked keg $formula (something on PATH was shadowing it)..."
    brew link --overwrite "$formula" || errcho "brew link --overwrite $formula failed."
  done <<< "$unlinked"
  orphaned="$(awk '
    /^Warning: Some installed kegs have no formulae!$/ {flag=1; next}
    flag && /^Warning:/ {flag=0}
    flag && /^  [A-Za-z0-9_@.+-]+$/ {sub(/^ +/, ""); print}' <<< "$doctor")"
  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue
    eccho "Uninstalling orphaned keg $formula (no source formula in any tapped tap)..."
    brew uninstall --ignore-dependencies --force "$formula" || errcho "brew uninstall $formula failed."
  done <<< "$orphaned"
  # Print the same report (fixes used to run doctor, then doctor again just to display).
  printf '%s\n' "$doctor"
}

# Homebrew taps - add those needed and remove obosoleted that can create conflicts (example: java8)
function checkBrewTaps {
  notaps=(
    caskroom/caskroom
    caskroom/versions
    homebrew/cask-drivers
    homebrew/cask-fonts
    homebrew/cask-versions
    homebrew/homebrew-cask-fonts
    homebrew/homebrew-cask-versions
    homebrew/homebrew-services # services is built into Homebrew core; standalone tap is deprecated
    homebrew/services          # same tap, canonical name -- untap to drop the deprecated "master" branch checkout
    wata727/tflint             # tflint is now in homebrew-core; this tap is dead upstream
  )
  brew_tap_file="$GOOD_MORNING_TEMP_FILE_PREFIX""brew_tap"
  brew tap > "$brew_tap_file"
  for tap in "${notaps[@]}"; do
    if grep -qE "^$tap$" "$brew_tap_file"; then
      brew untap "$tap"
    fi
  done
  # No third-party taps required at the moment; everything good-morning installs is in homebrew-core / homebrew-cask.
  taps=()
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
  if brew outdated | grep -q .; then
    brew upgrade
    BREW_CLEANUP_NEEDED=1
    # Doctor is slow. Run once after upgrades, fix from that output, then print it.
    eccho "Running Homebrew Doctor since Homebrew updates were installed..."
    fixBrewDoctorIssues
  fi
  eccho "Checking for outdated Homebrew Casks..."
  while IFS= read -r outdatedCask; do
    if [[ -n "$outdatedCask" ]]; then
      eccho "Upgrading $outdatedCask..."
      # Prefer upgrade. Reinstall is the old reliable path when upgrade fails or is unsupported.
      if ! brew upgrade --cask "$outdatedCask"; then
        eccho "brew upgrade --cask failed for $outdatedCask, falling back to reinstall..."
        brew reinstall "$outdatedCask"
      fi
      BREW_CLEANUP_NEEDED=1
    fi
  done < <(brew outdated --cask | sed -E 's/^([^ ]*) .*$/\1/')
fi

# Homebrew cask depends_on fix from: https://github.com/Homebrew/homebrew-cask/issues/58046
# The wireshark 3.0.0 install was the first cask that started to fail to update, but now succeeds with the following
# fix applied.
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
  docker-desktop
  # dropbox   dropbox.com returns 403 on install
  # etcher # Flash OS images to SD cards & USB drives, safely and easily.
  # firefox
  font-fira-code
  # google-backup-and-sync
  # google-chrome
  gpg-suite
  handbrake
  iterm2
  # keybase
  # keyboard-maestro # keyboard macros
  # logitech-gaming-software # if you plug-in a logitech keyboard
  # microsoft-office
  # microsoft-teams
  # omnifocus
  # omnigraffle
  # onedrive
  # openconnect-gui # connect to a Cisco Connect VPN
  # opera
  # parallels
  # postman
  # qladdict # Need to check all these quick-look extensions for Big Sur compatibility.
  # qlcolorcode
  # qlmarkdown
  # qlstephen
  # quicklook-json
  # rocket # utf-8 emoji quick lookup and insert in any macOS app
  # sketch
  # slack
  # sourcetree
  # tableplus
  the-unarchiver
  # transmission # open source BitTorrent client from https://github.com/transmission/transmission
  # tunnelblick # connect to your VPN
  # vanilla # hide menu icons on your mac
  visual-studio-code
  # visual-studio-code-insiders
  # wireshark
  # xmind-zen
  # zoom
)
cask_list_temp_file="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_list"
cask_collision_file="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_collision"
brew list --cask > "$cask_list_temp_file"

# Uninstall specific Homebrew casks that conflict with this script if installed.
problem_casks=(
  insomniax # remove since this is now unmaintained
  keeweb # upstream looking for new maintainer since 2022, no commits in 2026; security smell for a password manager
  provisionql # cask deprecated/disabled upstream; no Tahoe-compatible quick-look extension
  skitch # dev stopped at v2.9 in 2020; fails to launch on macOS Tahoe
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
cask_install_log="$GOOD_MORNING_TEMP_FILE_PREFIX""cask_install_log"
for cask in "${casks[@]}"; do
  if ! grep -qE "(^| )$cask($| )" "$cask_list_temp_file"; then
    eccho "Installing $cask with Homebrew..."
    # Tee keeps install output visible. PIPESTATUS[0] is brew (piping to grep alone used to hide failures).
    brew install --cask "$cask" 2>&1 | tee "$cask_install_log"
    cask_install_status=${PIPESTATUS[0]}
    grep -E "Error: It seems there is already an App at '.*'\." "$cask_install_log" \
      | sed -E "s/.*'(.*)'.*/\1/" > "$cask_collision_file"
    if [[ -s "$cask_collision_file" ]]; then
      # Remove non-brew installed version of app and retry.
      sudoit rm -rf "$(cat "$cask_collision_file")"
      rm -f "$cask_collision_file"
      brew install --cask "$cask"
      cask_install_status=$?
    fi
    if (( cask_install_status == 0 )); then
      NEW_BREW_CASK_INSTALLS=1
      BREW_CLEANUP_NEEDED=1
    else
      errcho "Homebrew cask install failed for $cask."
    fi
  fi
done
rm -f "$cask_collision_file" "$cask_list_temp_file" "$cask_install_log"
unset cask_collision_file
unset cask_install_log
unset cask_install_status

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
  local installed=0
  if grep -qE "(^| )$formula_name($| )" "$formula_list_temp_file"; then
    installed=1
  fi
  # Install only when missing; uninstall only when present.
  if { [[ "$brew_command" == "install" ]] && (( installed == 0 )); } \
    || { [[ "$brew_command" == "uninstall" ]] && (( installed == 1 )); }; then
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

# Detect Homebrew formulas still linked against openssl@1.1 (now uninstalled) and reinstall them so they relink
# against the current openssl. Returns early when openssl@1.1 is still present (links resolve fine). Uses `otool -L`
# against Mach-O files in each keg's bin/sbin/lib/libexec so only real LC_LOAD_DYLIB dependencies are matched (no false
# positives from header text or docs). Parallelism via `xargs -P` keeps it fast.
function rebuildBrokenOpensslLinks {
  local brew_prefix cellar
  brew_prefix="$(brew --prefix 2> /dev/null)"
  cellar="$(brew --cellar 2> /dev/null)"
  if [[ -z "$brew_prefix" ]] || [[ -z "$cellar" ]] || ! [[ -d "$cellar" ]]; then
    return
  fi
  if [[ -d "$brew_prefix/opt/openssl@1.1" ]]; then
    return
  fi
  local affected
  affected="$(/usr/bin/find "$cellar"/*/* -type f \
      \( -path '*/bin/*' -o -path '*/sbin/*' \
         -o \( \( -path '*/lib/*' -o -path '*/libexec/*' \) \
              -a \( -name '*.dylib' -o -name '*.so' \) \) \
      \) -print0 2> /dev/null \
    | /usr/bin/xargs -0 -P 8 /usr/bin/otool -L 2> /dev/null \
    | /usr/bin/awk -v pat='lib(ssl|crypto)\\.1\\.1\\.dylib' \
        'sub(/:$/, "") { fname = $0; next } $0 ~ pat { print fname }' \
    | sed -E "s|^${cellar}/([^/]+)/.*|\1|" \
    | sort -u)"
  if [[ -z "$affected" ]]; then
    return
  fi
  eccho "These Homebrew formulas are still linked against openssl@1.1 and"
  eccho "will be reinstalled to relink against the current openssl:"
  eccho "$affected"
  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue
    brew reinstall "$formula"
  done <<< "$affected"
}

# Uninstall formulas that create conflicts and may or may not have been
# previously installed by earlier versions of this script.
problem_formulas=(
  bash-completion
  brew-cask-completion # deprecated upstream; built into modern Homebrew's tab-completion already
)
for formula in "${problem_formulas[@]}"; do
  ensureFormulaUninstalled "$formula"
done
unset problem_formulas

# shellcheck disable=SC2034
formulas=(
  # ansible
  # automake
  awscli # AWS CLI v2
  bash
  bash-completion@2
  caddy
  certbot # For generating SSL certs with Let's Encrypt
  coreutils
  # dialog # https://invisible-island.net/dialog/
  # deno
  direnv # https://direnv.net/
  fd # https://github.com/sharkdp/fd
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
  openssl@3
  sevenzip # provides 7zz command (replacement for unmaintained p7zip)
  # packer
  # packer-completion
  pandoc
  # pgcli
  # pgtune
  # pgweb
  pinentry-mac # GUI passphrase prompt for gpg-agent; required for commit signing outside a real TTY
  # pip-completion
  # pyenv
  python@3.14
  rbenv
  ruby-build
  readline # for pyenv installs of python and ruby-build
  # redis
  shellcheck # shell script linting
  # swagger-codegen # requires brew install --cask homebrew/cask-versions/adoptopenjdk8
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
  rebuildBrokenOpensslLinks
  eccho "Cleaning up Homebrew cache..."
  # The -s option clears even the latest versions of uninstalled formulas and casks. This does not clear the cache of
  # versions currently installed.
  brew cleanup -s
fi

# GPG signing setup. Runs after Homebrew installed gpg-suite (cask) so that both `gpg` and GPG Keychain.app are
# guaranteed to be present.
if [[ -n "$gpg_setup_wanted" ]]; then
  # gpg-suite may land on PATH only for new shells. Probe common locations in this sourced session.
  if ! type gpg &> /dev/null; then
    for gpg_bin in /usr/local/bin/gpg /opt/homebrew/bin/gpg /usr/local/MacGPG2/bin/gpg; do
      if [[ -x "$gpg_bin" ]]; then
        PATH="$(dirname "$gpg_bin"):$PATH"
        break
      fi
    done
    unset gpg_bin
  fi
  if ! type gpg &> /dev/null; then
    errcho "gpg was not found after installing GPG Suite. Open a new terminal or check PATH, then re-run."
  else
    eccho "Creating a GPG key for you to use when signing commits is an excellent way to guarantee the"
    eccho "integrity of your code changes for others."
    eccho "Learn more about this here: https://git-scm.com/book/tr/v2/Git-Tools-Signing-Your-Work"
    eccho "Learn about GitHub's use here: https://help.github.com/articles/generating-a-new-gpg-key/"
    if askto "create a GPG signing key for signing your git commits"; then
      eccho "Generating a GPG key for signing Git operations..."
      promptsecret "Enter a passphrase for the GPG key" GPG_PASSPHRASE
      if [[ -z "$GPG_PASSPHRASE" ]]; then
        errcho "GPG passphrase cannot be empty. Skipping GPG key setup."
        unset GPG_PASSPHRASE
      else
        gpg_status_file="$GOOD_MORNING_TEMP_FILE_PREFIX""gpg_status"
        if gpg --batch --status-fd 3 --gen-key 3>"$gpg_status_file" <<EOF
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
        then
          # KEY_CREATED P <fingerprint> from status-fd. Fallback: first fpr for this email.
          gpg_key_id=$(awk '/KEY_CREATED P / { print $4; exit }' "$gpg_status_file")
          if [[ -z "$gpg_key_id" ]]; then
            gpg_key_id=$(gpg --list-secret-keys --with-colons "$GIT_EMAIL" 2> /dev/null \
              | awk -F: '$1 == "fpr" { print $10; exit }')
          fi
          if [[ -z "$gpg_key_id" ]]; then
            errcho "Could not determine the new GPG key id. Not enabling git commit signing."
          else
            eccho "Signing key created."
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
            eccho "GPG signing is enabled. pinentry-mac will prompt for the passphrase on your first signed commit."
            eccho "Tick 'Save in Keychain' there if you want it cached for future commits."
          fi
          unset gpg_key_id
        else
          errcho "gpg --gen-key failed. Not enabling git commit signing."
        fi
        unset GPG_PASSPHRASE
        rm -f "$gpg_status_file"
        unset gpg_status_file
      fi
    fi
  fi
fi
unset gpg_setup_wanted

# Configure gpg-agent to use pinentry-mac for passphrase prompts when GPG commit signing is enabled. Required on
# macOS because gpg-agent spawns pinentry as a detached process with no controlling TTY, where the default curses
# pinentry cannot prompt and signing fails. Any existing pinentry-program directive in ~/.gnupg/gpg-agent.conf is
# preserved.
function ensureGpgPinentry {
  # Only relevant when GPG signing is configured for git.
  [[ -n "$(git config --global --get user.signingkey 2> /dev/null)" ]] \
    || [[ "$(git config --global --get commit.gpgsign 2> /dev/null)" == "true" ]] || return
  local agent_conf="$HOME/.gnupg/gpg-agent.conf" pinentry_path
  [[ -f "$agent_conf" ]] && grep -qE '^[[:space:]]*pinentry-program[[:space:]]' "$agent_conf" && return
  pinentry_path="$(brew --prefix 2> /dev/null)/bin/pinentry-mac"
  [[ -x "$pinentry_path" ]] || return
  eccho "Adding pinentry-program to ~/.gnupg/gpg-agent.conf (fixes 'Inappropriate ioctl' on commit signing)..."
  mkdir -p "$HOME/.gnupg" && chmod 700 "$HOME/.gnupg"
  printf 'pinentry-program %s\n' "$pinentry_path" >> "$agent_conf"
  chmod 600 "$agent_conf"
  gpgconf --kill gpg-agent 2> /dev/null || true
}
ensureGpgPinentry

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
  # Prefer the Homebrew Python's libexec pip
  local brew_pip
  for prefix in /opt/homebrew /usr/local; do
    for py in python@3.14 python@3.13 python@3.12 python@3.11; do
      brew_pip="$prefix/opt/$py/libexec/bin/pip"
      if [[ -x "$brew_pip" ]]; then
        echo "$brew_pip"
        return
      fi
    done
  done
  pickbin 'pip pip3 pip3.14 pip3.13 pip3.12 pip3.11'
}

eccho "Checking pip install..."
localpip="$(findpip)"
if [[ -z "$localpip" ]]; then
  eccho "No pip found; bootstrapping via get-pip.py..."
  wget https://bootstrap.pypa.io/get-pip.py --output-document ~/get-pip.py
  python ~/get-pip.py --user
  rm -f ~/get-pip.py
elif [[ "$localpip" == /opt/homebrew/* ]] || [[ "$localpip" == /usr/local/* ]]; then
  eccho "Using Homebrew Python pip at $localpip (brew owns updates, skipping self-upgrade)."
else
  eccho "Checking for update to pip at $localpip..."
  "$localpip" install --upgrade pip --upgrade-strategy eager > /dev/null
fi
unset localpip

export PYCURL_SSL_LIBRARY=openssl
# Some macOS Python installs (notably Homebrew's) ship an EXTERNALLY-MANAGED marker that makes pip refuse system-wide
# installs. Honor the documented escape hatch via env var so all pip invocations in this section (including pip-review,
# which calls pip internally) can install/upgrade global tools.
export PIP_BREAK_SYSTEM_PACKAGES=1
# Install pips in Python
piptempfile="$HOME/pipfreeze.temp"
$(findpip) freeze > "$piptempfile"
# Drop legacy pip packages that pin obsolete deps and fight pip-review
legacy_pips=(
  aws-shell
  awscli
)
for legacy_pip in "${legacy_pips[@]}"; do
  if grep -qiE "^${legacy_pip}==" "$piptempfile"; then
    eccho "Uninstalling legacy pip package $legacy_pip..."
    "$(findpip)" uninstall -y "$legacy_pip" > /dev/null
  fi
done
unset legacy_pips
pips=(
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
# SDKROOT is exported globally near the top of the script. We still need to
# point pip-built C extensions at brew's openssl headers/libs.
pip_openssl_prefix="$(brew --prefix openssl 2> /dev/null)"
for pip in "${pips[@]}"; do
  if ! grep -qi "$pip==" "$piptempfile"; then
    CFLAGS="-I$pip_openssl_prefix/include -O2" \
    LDFLAGS="-L$pip_openssl_prefix/lib" \
    "$(findpip)" install "$pip"
  fi
done
unset pips
rm -f "$piptempfile"
unset piptempfile

# Pin pip-review to the same Python whose pip we drove the installs with, otherwise PATH precedence (e.g. pyenv
# shims earlier than Homebrew) picks up a different `pip-review` and upgrades packages in some unrelated Python
# install -- which is how legacy awscli 1.x in a pyenv version keeps rolling forward and clobbering newer deps.
pip_review_bin="$(findpip)"
pip_review_bin="${pip_review_bin%/pip}/pip-review"
[[ -x "$pip_review_bin" ]] || pip_review_bin="$(command -v pip-review 2> /dev/null)"
if [[ -x "$pip_review_bin" ]] && ! "$pip_review_bin" | grep -q "Everything up-to-date"; then
  eccho "Upgrading pip installed packages via $pip_review_bin..."
  CFLAGS="-I$pip_openssl_prefix/include -O2" \
  LDFLAGS="-L$pip_openssl_prefix/lib" \
  "$pip_review_bin" --auto
fi
unset pip_review_bin
unset pip_openssl_prefix
# Drop pip environment variables that may have been set
unset PIP_BREAK_SYSTEM_PACKAGES
unset PYCURL_SSL_LIBRARY

function upgradeNPM {
  eccho "Checking Node.js $(node -v) global npm package versions..."
  # Upgrade all global packages other than npm to latest
  while IFS= read -r package; do
    if [[ -n "$package" ]]; then
      eccho "Upgrading global package $package for Node.js $(node -v)..."
      npm install "$package" --global
    fi
  done < <(npm --global outdated --parseable --depth=0 | cut -d: -f4)
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
        # In this case, the version that was active will be uninstalled. Track the new one as the active_version.
      active_version="$new_version"
    fi
    local reinstall_version
    reinstall_version="$(if [[ "$old_version" == "N/A" ]]; then echo "$active_version"; else echo "$old_version"; fi)"
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
  # https://github.com/nvm-sh/nvm#install--update-script
  eccho "Installing Node Version Manager v$nvm_version"
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_version}/install.sh" | bash
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
  eccho "2. In Preferences > Profiles > Terminal, set the iTerm buffer scroll back to 100000."
  eccho "3. Run the Install Shell Integration command from the iTerm2 menu."
  eccho "4. Use iTerm instead of Terminal from now on. Learn more here: https://iterm2.com/"
  prompt "Hit Enter to continue..."
  # todo: insert directly into plist located here $HOME/Library/Preferences/com.googlecode.iterm2.plist
  # todo: change plist directly for scroll back Root > New Bookmarks > Item 0 > Unlimited Scrollback > Boolean YES
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
    # Listing quarantined apps needs no elevation, so we compute the full worklist up front. If nothing is quarantined
    # we return before touching sudo at all, guaranteeing no password prompt when there is nothing to approve.
  local apps=()
  local failed=()
  IFS=$'\n'
  # shellcheck disable=SC2207
  apps=($(xattr -v -- /Applications/* 2> /dev/null | grep "com.apple.quarantine" | \
    sed -E 's/^(.*): com.apple.quarantine$/\1/'))
  unset IFS
  (( ${#apps[@]} == 0 )) && return
  eccho "Auto-approving applications for Gatekeeper..."
  local app app_name
  for app in "${apps[@]}"; do
    app_name="$(echo "$app" | sed -E 's|/Applications/(.*)\.app|\1|')"
    eccho "Approving $app_name..."
      # Most user-installed apps can have their quarantine bit cleared as the normal user, so try that first and only
      # fall back to sudoit (which reuses the cached credential from earlier, so it should not re-prompt) for the ones
      # that genuinely need elevation. On modern macOS some apps' quarantine bit is protected by SIP and cannot be
      # cleared even via sudo (xattr returns EPERM); suppress the noise and surface a single manual-approval hint later.
    if xattr -d com.apple.quarantine "$app" 2> /dev/null; then
      continue
    fi
    if ! sudoit xattr -d com.apple.quarantine "$app" 2> /dev/null; then
      failed+=("$app_name")
    fi
  done
  if (( ${#failed[@]} > 0 )); then
    eccho "Could not auto-approve these apps (Gatekeeper protected on modern macOS):"
    for app_name in "${failed[@]}"; do
      eccho "  - $app_name"
    done
    eccho "Open each app manually from /Applications, then click 'Open' in the"
    eccho "Gatekeeper dialog (or approve via System Settings > Privacy & Security)."
  fi
}

function reindexSpotlight {
  eccho "Triggering a rebuild of the Spotlight index to ensure all new brew casks appear..."
  sudoit mdutil -E /
}

# Spotlight Search Privacy paths to exclude from indexing
SPOTLIGHT_VOLUME_CONFIG="/System/Volumes/Data/.Spotlight-V100/VolumeConfiguration.plist"
spotlight_exclusion_paths=(
  "/opt/homebrew" "/usr/local/Homebrew" "$HOME/.bundle" "$HOME/.cache" "$HOME/.claude" "$HOME/.codeium" "$HOME/.codex"
  "$HOME/.cursor" "$HOME/.docker" "$HOME/.dotnet" "$HOME/.gem" "$HOME/.gradle" "$HOME/.k8slens" "$HOME/.local"
  "$HOME/.mono" "$HOME/.npm" "$HOME/.nuget" "$HOME/.nvm" "$HOME/.pyenv" "$HOME/.rbenv" "$HOME/.terraform.d"
  "$HOME/.vscode" "$HOME/.vscode-shared" "$HOME/.windsurf" "$HOME/go" "$HOME/Library/Application Support"
  "$HOME/Library/Caches" "$HOME/Library/Containers" "$HOME/Library/Developer" "$HOME/Library/Group Containers"
  "$HOME/Parallels" "$REPO_ROOT"
)

function checkSpotlightExclusions {
  eccho "Checking Spotlight Search Privacy list..."
  # Reading the plist needs sudo + Full Disk Access, so doing it every run means a password prompt every run. Instead we
  # hash the desired set (recommended paths that currently exist) and skip the sudo-gated read/write when it matches the
  # hash from the last reconciliation. It only changes when the list is edited or a path appears/disappears -- i.e. when
  # a re-check is actually warranted.
  local desired=() p
  for p in "${spotlight_exclusion_paths[@]}"; do
    [[ -e "$p" ]] && desired+=("$p")
  done
  local desired_hash
  desired_hash="$(printf '%s\n' "${desired[@]}" | sort -u | shasum -a 256 | cut -d ' ' -f 1)"
  if [[ -n "$desired_hash" && "$desired_hash" == "$(getConfigValue "spotlight_exclusions_hash")" ]]; then
    eccho "Spotlight exclusions unchanged since last reconciliation; skipping."
    return
  fi
  # /System/Volumes/Data/.Spotlight-V100/ is TCC-protected; even sudo cannot
  # read it unless the calling terminal has Full Disk Access.
  local plist_xml current missing=()
  if ! plist_xml="$(sudoit plutil -extract Exclusions xml1 -o - \
      "$SPOTLIGHT_VOLUME_CONFIG" 2> /dev/null)"; then
    local app="${TERM_PROGRAM:-your terminal}"
    case "$app" in
      iTerm.app) app="iTerm" ;; Apple_Terminal) app="Terminal" ;;
      vscode) app="VS Code / Cursor" ;;
    esac
    errcho "Cannot read Spotlight config; grant Full Disk Access to $app via"
    errcho "System Settings > Privacy & Security > Full Disk Access, then re-run."
    askto "open the Full Disk Access settings pane now" \
      "open 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles'"
    return
  fi
  current="$(sed -nE 's/.*<string>([^<]*)<\/string>.*/\1/p' <<< "$plist_xml")"
  if [[ -n "$current" ]]; then
    eccho "Spotlight Search Privacy currently excludes:"
    while IFS= read -r p; do eccho "  $p"; done <<< "$current"
  fi
  for p in "${desired[@]}"; do
    ! grep -Fxq "$p" <<< "$current" && missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    # Everything we recommend is already excluded; remember this set so future runs can skip the sudo-gated read.
    eccho "All recommended Spotlight exclusions in place."
    setConfigValue "spotlight_exclusions_hash" "$desired_hash"
    return
  fi
  eccho "Recommended exclusions missing from Spotlight Privacy:"
  for p in "${missing[@]}"; do eccho "  $p"; done
  if askto "add these to the Spotlight Search Privacy list"; then
    local add_failed=
    for p in "${missing[@]}"; do
      if ! sudoit /usr/libexec/PlistBuddy -c "Add :Exclusions: string \"$p\"" \
        "$SPOTLIGHT_VOLUME_CONFIG"; then
        add_failed=1
        errcho "Failed to exclude $p from Spotlight Privacy."
      fi
    done
    sudoit launchctl kickstart -k system/com.apple.metadata.mds > /dev/null 2>&1
    # Only remember the set when every add succeeded, otherwise the next run would skip a still-missing path.
    if [[ -z "$add_failed" ]]; then
      setConfigValue "spotlight_exclusions_hash" "$desired_hash"
    fi
  fi
}

if [[ -n "$NEW_BREW_CASK_INSTALLS" ]]; then
  unset NEW_BREW_CASK_INSTALLS
  # Moved this lower since it's not important to do this earlier in the script
  # and it might avoid prompting for the password until more of the work is done.
  reindexSpotlight
fi
approveAllApps
  # Check permissions again since new installs and updates will often undo these important changes.
checkPerms
checkSpotlightExclusions

# Opinionated defaults only on first clone, or when GOOD_MORNING_APPLY_DEFAULTS is set.
# Daily alias sets GOOD_MORNING_RUN and must not re-blast Dock/Finder prefs on every run.
if [[ -n "$FIRST_RUN" ]] || [[ -n "$GOOD_MORNING_APPLY_DEFAULTS" ]]; then

  eccho "Optimizing System Settings"
  eccho "Only show icons of running apps in app bar, using Spotlight to launch"
  defaults write com.apple.dock static-only -bool true
  eccho "Do not auto-hide the menu bar"
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
  # Each -dict replaces the whole domain key. Set both timers in one write per power source.
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict \
    "Display Sleep Timer" -int 60 \
    "System Sleep Timer" -int 60
  sudoit defaults write /Library/Preferences/com.apple.PowerManagement "AC Power" -dict \
    "Display Sleep Timer" -int 180 \
    "System Sleep Timer" -int 180
  eccho "Show battery percentage"
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"
  eccho "Turn off the boot sound effect"
  sudoit nvram SystemAudioVolume=" "

  eccho "Restart your computer to see all the changes."
fi
unset GOOD_MORNING_APPLY_DEFAULTS

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
  # Read keep_pass before unsetting GOOD_MORNING_CONFIG_FILE (getConfigValue needs the path).
  local keep_pass_for_session
  keep_pass_for_session="$(getConfigValue 'keep_pass_for_session')"

  unset FIRST_RUN
  unset GIT_EMAIL
  unset GITHUB_KEYS_URL
  unset GIT_NAME
  unset GOOD_MORNING_CONFIG_FILE
  unset GOOD_MORNING_TEMP_FILE_PREFIX
  unset GOOD_MORNING_REPO_ROOT
  # Drop pip environment variables that may have been set
  unset PIP_BREAK_SYSTEM_PACKAGES
  unset PYCURL_SSL_LIBRARY

  if [[ "$keep_pass_for_session" != "yes" ]]; then
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
    # Self-update last on purpose. Save path before cleanupEnvVars unsets it, and always popd
    # so a failed git pull cannot leave a sourced shell stuck in this repo.
    eccho "Almost done! Pulling latest for good-morning repository..."
    cleanupTempFiles
    local repo_root="$GOOD_MORNING_REPO_ROOT"
    cleanupEnvVars
    if [[ -z "$repo_root" ]] || ! [[ -d "$repo_root/.git" ]]; then
      errcho "good-morning repo root missing or not a git checkout: ${repo_root:-"(unset)"}"
    elif pushd "$repo_root" > /dev/null; then
      git pull || errcho "git pull in $repo_root failed."
      popd > /dev/null || errcho "popd failed after updating $repo_root."
    else
      errcho "Could not enter good-morning repo at $repo_root; skipping pull."
    fi
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
  eccho "Run log: $GOOD_MORNING_LOG_FILE"
}
greeting

gm_restore_stdio
gm_clear_run_traps
