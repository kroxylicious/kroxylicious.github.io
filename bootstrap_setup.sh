#!/bin/bash

export BOOTSTRAP_VERSION="v5.3.2"

# download the full Bootstrap 5 sources (including JS)
echo "Downloading Bootstrap $BOOTSTRAP_VERSION sources from GitHub..."
wget "https://github.com/twbs/bootstrap/archive/$BOOTSTRAP_VERSION.zip"

# unpack the sources into the _sass/ directory
echo "Unpacking sources..."
unzip "$BOOTSTRAP_VERSION.zip" -d ./_sass

# make a directory to put the Bootstrap 5 Sass sources into
mkdir ./_sass/bootstrap

# move the Sass sources to your new directory
mv ./_sass/bootstrap-5.3.2/scss ./_sass/bootstrap/scss

# delete all the other Bootstrap sources (i.e. except the Sass ones, which we moved)
echo "Cleaning up..."
rm -r ./_sass/bootstrap-5.3.2

# delete the downloaded zip
rm v5.3.2.zip

echo "Done!"