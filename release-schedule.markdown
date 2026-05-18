---
layout: default
title: Release Schedule
permalink: /release-schedule/
---

<div class="container-xxl krx-gutter py-5">
  <div class="row">
    <div class="col">
      <h1>Release Schedule</h1>
      <p>This page documents the planned and released versions of Kroxylicious.</p>

      <div class="table-responsive mt-4">
        <table class="table table-striped table-hover">
          <thead>
            <tr>
              <th scope="col">Release</th>
              <th scope="col">Planned Release Date</th>
              <th scope="col">Milestone</th>
              <th scope="col">Status</th>
            </tr>
          </thead>
          <tbody>
            {%- for release in site.data.release-schedule.releases -%}
            {%- assign underscored_version = release.version | replace: '.', '_' -%}
            <tr>
              <td>Kroxylicious {{ release.version }}</td>
              <td>{{ release.plannedDate }}</td>
              <td><a href="{{ release.milestoneUrl }}">{{ release.version }}</a></td>
              <td>
                {%- if site.data.release[underscored_version] -%}
                <span class="badge bg-success">Released</span>
                {%- else -%}
                <span class="badge bg-info">Planned</span>
                {%- endif -%}
              </td>
            </tr>
            {%- endfor -%}
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
