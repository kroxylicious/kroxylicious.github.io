---
layout: default
title: Release Archives
---

{%- comment -%}
`sort_by_semver_key` is a custom filter in _plugins.
{%- endcomment -%}
{%- assign sorted_releases = site.data.release | sort_by_semver_key -%}

<div class="row align-items-start justify-content-center my-5">
  <div class="col-lg-3 mb-5" role="complementary" aria-labelledby="page-title">
    <div class="card shadow px-2 mx-2">
      <div class="card-body">
      <h1 id="page-title" class="fs-3">{{ page.title }}</h1>
      <ul>
{% for rel_entry in sorted_releases %}
{%- assign releaseVersion=rel_entry[0] | replace: '_', '.' -%}
<li><a href="#{{ releaseVersion }}">{{ releaseVersion }}</a></li>
{%- endfor -%}
      </ul>
      </div>
    </div>
  </div>
  <div class="col-lg-6" role="main">
{% for rel_entry in sorted_releases %}
{%- assign releaseVersion=rel_entry[0] | replace: '_', '.' -%}
{%- assign release=site.data.release | map: relKey -%}
    <div class="card shadow mb-4">
      <div class="card-body mx-3 my-2">
<h2 id="{{ releaseVersion }}" class="card-title fs-4">{{ releaseVersion }}
{%- if releaseVersion == site.data.kroxylicious.latestRelease %} (latest release){%- endif -%}
</h2>
<a href="{{ '/documentation/' | append: releaseVersion | append: '/' | absolute_url }}">Documentation</a><br/>
<a href="{{ '/download/' | append: releaseVersion | append: '/' | absolute_url }}">Download</a>
      </div>
    </div>
{%- endfor -%}
  </div>
</div>
