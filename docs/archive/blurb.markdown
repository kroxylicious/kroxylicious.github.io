{% assign latest_release_version = site.data.kroxylicious.versions | where: "development", nil | first %}
{% assign last_unarchived_version = site.data.kroxylicious.versions | where: "archive", nil | last %}

Documentation for all versions of Kroxylicious prior to {{ last_unarchived_version.title }} can be found here.

The documentation linked here is for older releases of Kroxylicious, and may not reflect current functionality.

The Kroxylicious project recommends using the latest stable release to ensure you stay up-to-date with the latest features and bugfixes. The latest release version of Kroxylicious is {{ latest_release_version.title }}, you can find the documentation for this latest stable release [here]({{ latest_release_version.url | absolute_url }}).