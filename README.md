# Kroxylicous.io Site

## What?

This is the repo containing the kroxylicious.io website.
The site runs on Jekyll, so you'll need to ensure you have the [prerequisites](https://jekyllrb.com/docs/) installed to try it locally.
You'll also need to ensure you have Ruby 3.2+ installed, along with the latest versions of Rake and Bundler for your Ruby distribution.

## Key Files
- [Gemfile](Gemfile) - required ruby gems for building and serving the site
- [_config.yml](_config.yml) - Jekyll configuration for building the site
- [_sass/kroxylicious.scss](_sass/kroxylicious.scss) - configuring CSS with kroxy colours
- [.github/workflows/jekyll-gh-pages.yml](.github/workflows/jekyll-gh-pages.yml) - workflow for building and deploying to GitHub Pages

## Development

Built with Jekyll, Bootstrap 5, and Ruby 3.2

There is a GitHub action that builds and deploys the HTML/CSS
to the `gh-pages` branch on push to `main`.

We don't use the Bootstrap 5 ruby gem here, as it runs on a
`dart-sass` implementation that's incompatible with the one Jekyll uses.

### Running Locally

To run the site locally, you'll first need to download the Bootstrap 5 Sass sources by running [bootstrap_setup.sh](bootstrap_setup.sh).

Then install the site's prerequisites by running this:

```bash
bundle install
```

You can then run the site with this command (don't close the terminal once you've run this, or the process serving the site will terminate):

```bash
bundle exec jekyll serve
```