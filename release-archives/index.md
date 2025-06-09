---
layout: default
title: Release Archives
---

<div class="row align-items-start justify-content-center my-5">
  <div class="col-lg-3 mb-5" role="complementary" aria-labelledby="page-title">
    <div class="card shadow px-2 mx-2">
      <div class="card-body">
      <h1 id="page-title" class="fs-3">{{ page.title }}</h1>
      <ul>
{% for release in site.data.release.list %}
<li><a href="#{{ release.version }}">{{ release.version }}</a></li>
{% endfor %}
</ul>
      </div>
    </div>
  </div>
  <div class="col-lg-6" role="main">
{% for release in site.data.release.list %}
    <div class="card shadow mb-4">
      <div class="card-body mx-3 my-2">
<h2 id="{{ release.version }}" class="card-title fs-4">{{ release.version }}{% if release.version == site.data.release.latest %} (latest release){% endif %}</h2>
<a href="/documentation/{{ release.version }}/">Documentation</a><br/>
<a href="/download/{{ release.version }}/">Download</a>
      </div>
    </div>
{% endfor %}
  </div>
</div>
