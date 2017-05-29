#!/bin/bash
# Read Password for sudo usage
read -r -s -p "Password: " PASSWORD

# Install Apple software updates
# This only works if updates were already detected by the Mac App Store
# You will generally rely on the auto-update system feature which setup.sh enables.
echo "$PASSWORD" | sudo -S -p "" softwareupdate -i -a

# Install iTunes App Store updates
# This only works if updates were already detected by the Mac App Store
# You will generally rely on the auto-update system feature which setup.sh enables.
mas upgrade

# Update all the Atom packages
yes | apm update -c false

# todo: Update Office

# update AWS CLI
echo "$PASSWORD" | sudo -H -S -p "" pip install --upgrade awscli

brew update
brew upgrade --cleanup
