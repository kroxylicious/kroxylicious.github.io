This is the repo for the website associated with Kroxylicious. 
Kroxylicious is a Layer 7 proxy for the Kafka protocol.
The website uses Jekyll and is hosted on github.

The content in this repo is a mixture of two things:

* static markdown and HTML content, which doesn't change much between releases of the Kroxylicious software.
* version-specific documentation, where a new release of the Kroxylicious software produces new documentation about that version.

The version-specific content has index pages enumerating the downloads and documentation publications, which is templated using liquid templates.

When you make a change you should test it. 
The script `./run.sh` can be used to serve the site from a docker container. 
The preview site can then be accessed at `http://127.0.0.1:4000/`.

This GitHub repository is hosted on GitHub at `https://github.com/kroxylicious/kroxylicious.github.io`.
You can use the `gh` tool to interact with GitHub PRs.
Note that we do not use the website repo for issues. 
Instead, issues for the website are held in the main Kroxylicious repo `https://github.com/kroxylicious/kroxylicious`.
So if you need to interact with website issues you can use the `-R kroxylicious/kroxylicious` option, for example: `gh issue list -R kroxylicious/kroxylicious`.
