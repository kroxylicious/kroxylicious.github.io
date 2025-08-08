# Kroxylicous.io Site

## What?

This is the repo containing the kroxylicious.io website.
The site runs on Jekyll, so you'll need to ensure you have the [prerequisites](https://jekyllrb.com/docs/) installed to try it locally.
You'll also need to ensure you have Ruby 3.2+ installed, along with the latest versions of Rake and Bundler for your Ruby distribution.

<!-- TOC -->
* [Kroxylicous.io Site](#kroxylicousio-site)
  * [What?](#what)
  * [Key Files](#key-files)
  * [Development](#development)
    * [Running in a Container](#running-in-a-container)
    * [Building Production HTML](#building-production-html)
    * [Running on GitHub Pages on a Fork](#running-on-github-pages-on-a-fork)
* [Binary content](#binary-content)
* [Excalidraw images](#excalidraw-images)
* [Redirects](#redirects)
* [Issues](#issues)
* [Contributing](#contributing)
<!-- TOC -->

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

When developing website content (editing markdown/asciidoc, modifying ruby extensions) it is useful to deploy a
local testing server that presents the website, with hot-reloading so that source changes are reflected quickly
in the built HTML.

To build and serve the website from a container you can run `./run.sh`. It will be deployed on http://localhost:4000

This assumes the use of `podman`, if you are a `docker` user you can run `CONTAINER_ENGINE=docker ./run.sh`.

### Building Production HTML

When developing build automation, it is useful to be able to build the static website output, that will be deployed to production, the
same way it will be built in GitHub Actions.

To build the production site you can run `./build.sh` which will produce an `_site` directory containing the built website for production.

This assumes the use of `podman`, if you are a `docker` user you can run `CONTAINER_ENGINE=docker ./build.sh`.

### Running on GitHub Pages on a Fork

When developing build automation, it is useful to be able to deploy your changes to the GitHub Pages a Fork of this repository. This
exercises all the production artifact creation and Pages deployment parts of the automation.

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

# Redirects
There is nothing more frustrating than reading some documentation or a stack trace with a link to some helpful sounding answer only for that link to be a 404. To try and minimise that pain we have built a Jekyll plugin to generate a redirect from a token to a URL. This plug-in generates a collection of static pages derived from the yaml documents in `_data/redirects`.
Each yaml document defines a namespace for redirections. For example `errors.yaml` will build pages under `/redirects/errors/`. The yaml document takes the format outlined here:

```yaml
baseUrl: https://kroxylicious.io/documentation/ #The base URL to build redirects from
delay: 3 #How long should the re-direction message be shown before loading the target. Defaults to 1.
mappings:
- name: test #the token to be the landing url
  fromVersion: 0.10.0 #Optional, if not specified the latest release at time of site build is used. 
  toVersion: 0.12.0 #Optional, if not specified the latest release at time of site build  is used.
  path: /html/kroxylicious-proxy/#con-configuring-client-connections-proxy # the path within the baseUrl
```

# Issues

Issues are tracked in the `kroxylicious/kroxylicious` [Issue tracker](https://github.com/kroxylicious/kroxylicious/issues)

# Contributing

We welcome contributions! Please see our [contributing guidelines](https://github.com/kroxylicious/.github/blob/main/CONTRIBUTING.md) to get started.