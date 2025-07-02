#!/bin/bash

export BOOTSTRAP_VERSION="5.3.7"

#Remove any existing Bootstrap sources
rm -f "v$BOOTSTRAP_VERSION.zip"
rm -rf ./_sass/bootstrap

# download the full Bootstrap 5 sources (including JS)
echo "Downloading Bootstrap v$BOOTSTRAP_VERSION sources from GitHub..."
wget "https://github.com/twbs/bootstrap/archive/v$BOOTSTRAP_VERSION.zip"

# unpack the sources into the _sass/ directory
echo "Unpacking sources..."
unzip "v$BOOTSTRAP_VERSION.zip" -d ./_sass

# make a directory to put the Bootstrap 5 Sass sources into
mkdir ./_sass/bootstrap

# move the Sass sources to your new directory
mv "./_sass/bootstrap-$BOOTSTRAP_VERSION/scss" ./_sass/bootstrap/scss

# delete all the other Bootstrap sources (i.e. except the Sass ones, which we moved)
echo "Cleaning up..."
rm -r "./_sass/bootstrap-$BOOTSTRAP_VERSION"

# delete the downloaded zip
rm "v$BOOTSTRAP_VERSION.zip"

echo "Done!"