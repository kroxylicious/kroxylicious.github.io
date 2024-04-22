# Rendering AsciiDoc on Kroxylicious.io

The way this works is that the entire `docs/` directory from a release version `$VERSION` of Kroxylicious gets put into this repository under `docs/$VERSION/_files/`, then an AsciiDoc file is created at `docs/$VERSION/index.adoc` which serves as the entrypoint for the `jekyll-asciidoc` plugin to begin processing. Finally, an update is made to `_data/kroxylicious.yml` to add the new version to the versions list.

## Docs Directories
The reason for the `_files/` subdirectories is to ensure that raw AsciiDoc files are not published by Jekyll. Unfortunately adding files to the `exclude` list in `_config.yml` prevents the `jekyll-asciidoc` plugin from processing them (even though the plugin's README implies that should not be the case, I simply couldn't get it to work), so we instead have to make use of Jekyll's convention that files and directories starting with an underscore will not be processed or served unless explicitly configured. However, this means we have to find a way to force the `jekyll-asciidoc` plugin into locating and processing them, because that underscore convention also applies to all Jekyll plugins. That's why we have the entrypoint `index.adoc` file in every version directory.

## Entrypoint File

The entrypoint `index.adoc` file must contain [front matter](https://jekyllrb.com/docs/front-matter/), a Jekyll convention (which might make your AsciiDoc linter throw a wobbly because Jekyll uses YAML syntax for front matter and AsciiDoc does not) which we're using to indicate to the `jekyll-asciidoc` plugin that these files are the only files that should be output as an individual HTML file (using the `require_front_matter_header: true` option, which prevents processing of files that don't have Jekyll-flavoured front matter). It also needs to include a reference to the actual documentation files in the `_files/` subdirectory. Lastly, it really does have to be named `index.adoc` (can't get creative here, sorry), or the site navigation will break.

The front matter should include -at minimum- the title of the page (i.e. `title: Kroxylicious Proxy $VERSION`), but can also include a `version_warning` which is just a message displayed at the top of the page telling the reader that the docs version they're reading is not for the latest release. You could also put any other page variables you want in here (though you'd have to modify `_layouts/docs.html` in order to use them), but I would avoid specifying a `permalink` because it could conflict with the information in `_data/kroxylicious.yml` and break the site navigation.

To force `jekyll-asciidoc` to render the actual documentation files (and not just this entrypoint file) we have to reference the actual index for the documentation files. This is done by having the line `include::_files/index.adoc[leveloffset=0]` as the _only_ (this is important) AsciiDoc content of the entrypoint file. If there's any other AsciiDoc content in there, it doesn't process the metadata of the `_files/index.adoc` file correctly and instead ends up displaying strings like `3.0, July 29, 2022: AsciiDoc article template :toc: :icons: font :url-quickref: https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/ :source-highlighter: pygments` in the final output HTML.

When you're done, your entrypoint `index.adoc` file should look something like this:

```
---
title: Kroxylicious Proxy $VERSION
version_warning: $THIS_IS_OPTIONAL
---
include::_files/index.adoc[leveloffset=0]
```

## Data File

The `_data/` directory is used by Jekyll for [site data](https://jekyllrb.com/docs/datafiles/), and the contents of any YAML, JSON, CSV, or TSV files in this directory will automatically be available across the site in the `site.data` variable.

In this case, we're using the contents of `_data/kroxylicious.yml` to generate a navigation dropdown with the names and URLs of each docs version. There isn't really a neater way to do this (I tried making the whole `docs` directory into a collection, but it ended up generating a nav link for each heading on each page...) so we have to keep this file in sync with the files in `docs/` so that the navigation is correctly rendered.

The update that needs to be made when new docs are added is pretty straightforward, a new entry is made in the `versions` list (try to keep it in order from most recent at the top (i.e. the development docs, followed by the latest release) and older versions at the bottom. Each entry consists of a `title` (i.e. `v0.5.1`) and a `url` (i.e. `/docs/v0.5.1/`).

The URL of a given version's docs will always consist of `/docs/`, followed by the version number (the same version number you used in the docs directory name I mentioned earlier), followed by a forward slash `/`.