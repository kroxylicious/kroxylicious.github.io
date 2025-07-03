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

Built with Jekyll, Bootstrap 5, and Ruby 3.4

There is a GitHub action that builds and deploys the HTML/CSS on push to `main`.

We don't use the Bootstrap 5 ruby gem here, as it runs on a
`dart-sass` implementation that's incompatible with the one Jekyll uses.

### Running in a Container

To build and serve the website from a container you can run `./run.sh`. It will be deployed on http://localhost:4000

This assumes the use of `podman`, if you are a `docker` user you can run `CONTAINER_ENGINE=docker ./run.sh`.

### Running on GitHub Pages on a Fork

To exercise the GitHub workflows and share changes it can be convenient to deploy a fork to GitHub Pages.

To enable pages on your fork:
1. go to `https://github.com/${yourname}/kroxylicious.github.io/settings` in a browser, replacing `${yourname}` with your GitHub username.
2. Navigate to "Pages" under "Code and automation"
3. Under "Build and deployment", under "Source", select "Github Actions".
4. Navigate to "Actions" under "Secrets and variables" under "Security"
5. Select the "Variables" tab
6. Click "New repository variable"
7. Create a new repository variable named `JEKYLL_CONFIG_OVERRIDES` with value:
   ```yaml
   baseurl: "kroxylicious.github.io"
   url: "https://${yourname}.github.io"
   ```
   replacing `${yourname}` with your GitHub username.
8. Push changes to any branch of your fork and then trigger a manual run of `https://github.com/${yourname}/kroxylicious.github.io/actions/workflows/jekyll-gh-pages.yml`,
   supplying the branch you want to checkout and deploy as a parameter. 

# Binary content

We have an ever-growing collection of binary assets, mostly images but also a few PDF slide decks etc all of these
should go under `/assets/`. To try and preserve a bit of sanity to the repo we subdivide `/assets` into sections for each class of conent.
- `/assets/pages/` - for binary assets related to the pages of the site.
- `/assets/theme/` - for binary assets included as part of the site theme
- `/assets/blog/` - for binary assets related to blog posts. Currently, blog has further sub dirs of `slides` & `images`.

# Excalidraw images

Some content such as the use-cases include diagrams drawn in Excalidraw.  Browsers can't handle the format natively, so instead, in addition to
commiting the `.excalidraw` orginals to the repo, we also export a transparent `.png` for inclusion in the content.

