#!/bin/bash

# THIS SETUP SCRIPT IS A WORK IN PROGRESS

# Install latest version of git

# Install node version manager
# https://github.com/creationix/nvm#install-script
if ! type "npm" > /dev/null; then
  echo "Installing NodeJS with Node Version Manager"
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.1/install.sh | bash
fi

# Install ControlPlane https://www.controlplaneapp.com/
# https://www.controlplaneapp.com/download/1.6.4?ref=sidebar
