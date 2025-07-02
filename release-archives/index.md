---
layout: default
title: Release Archives
---
{%- comment -%}
`site.data.release` an object and unordered.
Liquid lacks any ability to sort it, or convert it to an array for sorting. 
This following monstrosity is to work around that.
{%- endcomment -%}
{%- assign versionsList="" -%}
{%- for major in (0..999) -%}
  {%- assign probe1=major | append: "_1_0" -%}
  {%- if site.data.release[probe1] -%}
    {%- for minor in (1..999) -%}
      {%- assign probe2=major | append: "_" | append: minor | append: "_0" -%}
      {%- if site.data.release[probe2] -%}
        {%- for micro in (0..999) -%}
          {%- assign key=major | append: "_" | append: minor | append: "_" | append: micro -%}
          {%- if site.data.release[key] -%}
            {%- assign versionsList=versionsList | append: "," | append: key -%}
          {%- else -%}
            {%- break -%}
          {%- endif -%}
        {%- endfor -%}
      {%- else -%}
        {%- break -%}
      {%- endif -%}
    {%- endfor -%}
  {%- else -%}
    {%- break -%}
  {%- endif -%}
{%- endfor -%}
{%- assign versionsList=versionsList | remove_first: "," | split: "," | reverse -%}
{%- comment -%}
endmonstrosity
{%- endcomment -%}

<div class="row align-items-start justify-content-center my-5">
  <div class="col-lg-3 mb-5" role="complementary" aria-labelledby="page-title">
    <div class="card shadow px-2 mx-2">
      <div class="card-body">
      <h1 id="page-title" class="fs-3">{{ page.title }}</h1>
      <ul>
{%- for relKey in versionsList -%}
{%- assign releaseVersion=relKey | replace: '_', '.' -%}
<li><a href="#{{ releaseVersion }}">{{ releaseVersion }}</a></li>
{%- endfor -%}
      </ul>
      </div>
    </div>
  </div>
  <div class="col-lg-6" role="main">
{%- for relKey in versionsList -%}
{%- assign releaseVersion=relKey | replace: '_', '.' -%}
{%- assign release=site.data.release | map: relKey -%}
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
