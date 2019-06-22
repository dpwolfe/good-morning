# Good Morning

First thing to run on a new MacBook and every morning thereafter to keep it up to date.

## Pre-requisites

1. Your MacBook must be running macOS 10.14 (Mojave) or 10.15 (Catalina)
2. You must have admin privileges on your MacBook.
3. You must have an Apple ID that has accepted the developer agreement, which you can do
   for free here: <https://developer.apple.com/account/>

## Instructions

1. Install all system updates (_Apple Menu > System Preferences... > Software Update_).
2. Open up a Terminal session (_Command + Space_ for Spotlight Search and type "Terminal")
3. Run this command:

   ```sh
   curl -sL https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh | sh
   ```

## What does it do?

On the first run, it sets up a new MacBook with a list of commonly installed apps and
opinionated system settings. _It's automated, not unattended._ If you are a power user,
you'll probably like 95% of the system settings, which makes it well worth the trouble
of undoing a few that are not to your liking. Change the ones you don't like afterwards
and feel free to open issues for feedback.

### Avoid wasting hours manually installing and setting up the usual laundry list of tools like:

1. Xcode latest, plus the command line tools and, since Mojave, installs the C headers
   that are no longer present by default.
2. Node Version Manager (nvm) with latest Node.js and latest LTS of Node.js
3. Homebrew, installing a number of frequently used apps and utilities.
   - Includes: Microsoft Office, Docker, Visual Studio Code, Slack, Skype, Minikube + VirtuaBox,
     Spotify, Wireshark, Postman, iTerm2, Charles, DBeaver
4. Pyenv w/ Python 2.x and 3.x versions along with pip
5. A new SSH key and GPG key by walking you through their creation and the steps to add
   them to GitHub
6. Ruby Version Manager (rvm) with the latest Ruby
7. iTerm2
8. Primes your .bash_profile with some dotfiles containing aliases, git bash completion,
   environment variables, paths, etc.
   - Feel free to bring your own dotfiles or edit as needed after the first run.

### _Run good-morning... every morning_ to keep it all up-to-date, including:

1. Update Node Version Manager (nvm)
2. Update you to the latest Node.js and latest LTS of Node.js with nvm
   - Simple way to discover when a new Node.js version releases.
   - Globally installed packages are automatically re-installed into new Node.js versions.
   - The version that is immediately before any next version being installed will be uninstalled automatically.
     That only happens during an upgrade, so installs/re-installs of older versions are always left alone.
3. Update npm and globally installed node_modules in the latest Node.js and Node.js LTS.
4. Fix ownership to be yours on directories recommended by Homebrew or as discovered through trial and error.
5. Update apps (casks) installed via Homebrew in addition to brew formulas.
6. Update Python 2, 3 and pip versions. Occasionally fix the pip install since Python environments can be finicky.
7. Update Xcode, uninstalling the version immediately prior similar to how Node.js upgrades are performed.
8. Update Ruby and Ruby gems.
9. Keep installer caches clean, freeing up disk space.
10. Apply workarounds needed to keep the latest tools, apps or macOS version running solidly.
