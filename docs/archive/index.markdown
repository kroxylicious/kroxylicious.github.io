---
layout: docs
title: Kroxylicious Documentation Archive
permalink: /docs/archive/
is_archive: true
---
{% assign earliest_documented_version = site.data.kroxylicious.older_versions | last %}
{% capture earliest_docs_info %}
Please note this is the earliest Kroxylicious release documentation available on our website. Documentation sources for all versions, including those prior to {{ earliest_documented_version.title }}, are available from the Kroxylicious GitHub repository under their respective [release tags](https://github.com/kroxylicious/kroxylicious/releases).
{% endcapture %}

## Archived Release Documentation

{% for version in site.data.kroxylicious.older_versions %}
### Kroxylicious Proxy {{ version.title }}
{% if version.title == earliest_documented_version.title %}
{% include bs-alert.html type="info" icon="info-circle-fill" content=earliest_docs_info %}
{% endif %}
{% if version.subsections %}
{% for subsection in version.subsections %}
- [{{ subsection.title }}]({{ subsection.url }})
{% endfor %}
{% else %}
- [Documentation]({{ version.url }})
{% endif %}
{% if version.javadoc %}
- [Javadoc]({{ version.javadoc }})
{% endif %}
{% endfor %}