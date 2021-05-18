# Good Morning

First thing to run on a new MacBook and every morning thereafter to keep it up to date.

## Pre-requisites

_A fresh install of macOS is ideal, but not required._

- Your MacBook must be running macOS 10.15 (Catalina) or greater.
- You must have admin privileges on your MacBook.
- You must have an Apple ID that has accepted the developer agreement, which you can do
   for free here: <https://developer.apple.com/account/>
- A solid Internet connection at least for the first run since Xcode will be installed.

## Instructions

1. Install all system updates (_Apple Menu > System Preferences... > Software Update_).
2. Open up a Terminal session (_Command + Space_ for Spotlight Search and type "Terminal")
3. Run this command:

   ```sh
   curl -sL https://raw.githubusercontent.com/dpwolfe/good-morning/master/good-morning.sh | bash
   ```

## What does it do?

On the first run, it sets up a new MacBook with a list of commonly installed apps and
opinionated system settings. _It's automated, not unattended._ If you are a power user,
you'll probably like 95% of the system settings, which makes it well worth the trouble
of undoing a few that are not to your liking. Change the ones you don't like afterwards
and feel free to open issues for feedback.

### Avoid wasting hours manually installing and setting up the usual laundry list of tools like:

1. Xcode latest, plus the command line tools and for Mojave installs the C headers
   that were no longer present by default. Catalina does not have this problem.
2. Node Version Manager (nvm) with latest Node.js and latest LTS of Node.js
3. Homebrew, installing an opinionated number of popular used apps and utilities.
   - Includes: Microsoft Office, Docker, Visual Studio Code, Slack, Skype, Minikube + VirtualBox,
     Wireshark, Postman, iTerm2, Charles, TablePlus
4. A new SSH key and GPG key, walking you through their creation and the steps to add
   them to GitHub.
5. Primes your .bash_profile with references to dotfiles containing aliases, git bash completion,
   environment variables, paths, etc.
   - Feel free to bring your own dotfiles after the first run.

### _Run good-morning... every morning_ to keep it all up-to-date, including:

1. Update Node Version Manager (nvm)
2. Update you to the latest Node.js and latest LTS of Node.js with nvm
   - Simple way to discover when a new Node.js version releases.
   - Globally installed packages are automatically re-installed into new Node.js versions.
   - The version that is immediately before any next version being installed will be uninstalled automatically.
     That only happens during an upgrade. Installs/re-installs of older versions are untouched.
3. Update npm and globally installed node_modules in the latest Node.js and Node.js LTS.
4. Fix file and directory ownership to be yours where recommended by Homebrew or as I discovered through trial and error.
5. Update all Applications installed via Homebrew in addition to brew formulas.
6. Update Xcode, uninstalling the version immediately prior. This is similar to how Node.js upgrades are done.
   - You are only prompted if your Xcode version is lower than the last version supported on Catalina.
7. Update system Ruby gems.
8. Clean installer file caches, freeing up disk space.
9. Apply/re-apply workarounds needed to keep the latest tools, apps or macOS version working in harmony.
