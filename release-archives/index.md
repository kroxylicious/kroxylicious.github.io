---
layout: default
title: Release Archives
---
{% assign releases = "" | split: "" %}
{% for release in site.data.release %}
{% assign releases = releases | push: release[1] %}
{% endfor %}
{% assign releases = releases | sort: "rank" | reverse %}

<div class="row align-items-start justify-content-center my-5">
  <div class="col-lg-3 mb-5" role="complementary" aria-labelledby="page-title">
    <div class="card shadow px-2 mx-2">
      <div class="card-body">
      <h1 id="page-title" class="fs-3">{{ page.title }}</h1>
      <ul>
{%- for release in releases -%}
{%- assign releaseVersion=release.version -%}
<li><a href="#{{ releaseVersion }}">{{ releaseVersion }}</a></li>
{%- endfor -%}
      </ul>
      </div>
    </div>
  </div>
  <div class="col-lg-6" role="main">
{%- for release in releases -%}
{%- assign releaseVersion=release.version -%}
    <div class="card shadow mb-4">
      <div class="card-body mx-3 my-2">
<h2 id="{{ releaseVersion }}" class="card-title fs-4">{{ releaseVersion }}
{%- if releaseVersion == site.data.kroxylicious.latestRelease %} (latest release){%- endif -%}
</h2>
<a href="/documentation/{{ releaseVersion }}/">Documentation</a><br/>
<a href="/download/{{ releaseVersion }}/">Download</a>
      </div>
    </div>
{%- endfor -%}
  </div>
</div>
