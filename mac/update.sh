#!/bin/bash
# Read Password for sudo usage
stty -echo
printf "Password: "
read PASSWORD
stty echo
printf "\n"

# Install Apple software updates
echo $PASSWORD | sudo -S -p "" softwareupdate -i -a

# Install iTunes App Store updates
mas upgrade

# Update all the Atom packages
yes | apm update -c false

# todo: Update Office

# update AWS CLI
echo $PASSWORD | sudo -S -p "" pip install --upgrade awscli

