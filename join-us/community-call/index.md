---
layout: default
title: Community call
---
<link href='https://cdn.jsdelivr.net/npm/fullcalendar@6.1.10/index.global.min.css' rel='stylesheet' />
<script src='https://cdn.jsdelivr.net/npm/fullcalendar@6.1.10/index.global.min.js'></script>
<script src='https://cdn.jsdelivr.net/npm/ical.js@1.5.0/build/ical.min.js'></script>
<script src='https://cdn.jsdelivr.net/npm/@fullcalendar/icalendar@6.1.10/index.global.min.js'></script>
<script src='https://cdn.jsdelivr.net/npm/@fullcalendar/list@6.1.10/index.global.min.js'></script>
<script src='https://cdn.jsdelivr.net/npm/@fullcalendar/bootstrap5@6.1.10/index.global.min.js'></script>


<div class="row align-items-start justify-content-center my-5">
  <div class="col-lg-3 mb-5" role="complementary" aria-labelledby="page-title">
    <div class="card shadow px-2 mx-2">
      <div class="card-body">
        <h1 id="page-title" class="fs-3">{{ page.title }}</h1>
        <p>Sometimes it's just easier to talk face-to-face. 
        We have a virtual meeting every two weeks that's open to anyone to come along.</p>
        <p>The time alternates to try to accomodate people from different parts of the world, 
        so check the next-but-one if the next meeting is in the middle of your night.</p>
      </div>
    </div>
  </div>
  <div class="col-lg-6" role="main">
    <div>
      <p>We're using <a href="https://meet.jit.si/">Jitsi</a>, a free and open source video conferencing service.
      You don't need an account to join.</p>
      <div class="alert alert-warning" role="alert">
        <h4 class="alert-heading">Meetings are public (and recorded!)</h4>
        <p>Meetings are recorded and shared on <a href="https://www.youtube.com/@kroxylicious-io">our YouTube channel</a>.</p>
      </div>
    </div>
    <div class="d-flex flex-wrap align-items-center justify-content-between mb-4">
      <div>
        <h2 class="mb-1">Event Schedule</h2>
        <p class="text-muted mb-0">Local time: <strong id="tz-display">Detecting...</strong></p>
      </div>
      <div class="dropdown">
        <button class="btn btn-primary dropdown-toggle d-flex align-items-center" type="button" id="calendarDropdown" data-bs-toggle="dropdown" data-bs-auto-close="outside" aria-expanded="false">
          <i class="bi bi-calendar-plus me-2"></i> Add to Calendar</button>
        <ul class="dropdown-menu dropdown-menu-end shadow" aria-labelledby="calendarDropdown" style="min-width: 300px;">
          <li><h6 class="dropdown-header">Subscribe via App</h6></li>
          <li>
            <a class="dropdown-item d-flex align-items-center" href="{{ '/join-us/community-call/community-call.ics' | absolute_url | replace: 'http://', 'webcal://' | replace: 'https://', 'webcal://' }}">
              <i class="bi bi-apple me-2 text-dark"></i> Apple Calendar</a>
          </li>
          <li>
            <a class="dropdown-item d-flex align-items-center" href="https://www.google.com/calendar/render?cid={{ '/join-us/community-call/community-call.ics' | absolute_url }}" target="_blank">
              <i class="bi bi-google me-2 text-danger"></i> Google Calendar (Web)</a>
          </li>
          <li>
            <a class="dropdown-item d-flex align-items-center" href="{{ '/join-us/community-call/community-call.ics' | absolute_url | replace: 'http://', 'webcal://' | replace: 'https://', 'webcal://' }}">
              <i class="bi bi-microsoft me-2 text-dark"></i> Outlook (not Web)</a>
          </li>
          <li><hr class="dropdown-divider"></li>
          <li><h6 class="dropdown-header">Manual Setup</h6></li>
          <li class="px-3 py-2">
            <label for="calLink" class="form-label small text-muted">Copy Subscription URL:</label>
            <div class="input-group input-group-sm">
              <input type="text" class="form-control" value="{{ '/join-us/community-call/community-call.ics' | absolute_url }}" id="calLink" readonly>
              <button class="btn btn-outline-secondary" type="button" onclick="copyCalLink()" id="copyBtn">
                <i class="bi bi-clipboard"></i></button>
            </div>
            <div class="small">Using Outlook Web? Copy the link above, then in Outlook go to 'Add Calendar' &gt; 'Subscribe from web' and paste the link.</div>
            <div id="copyFeedback" class="small text-success mt-1 d-none">Link copied!</div>
          </li>
        </ul>
      </div>
    </div>
    <div id="calendar" class="border rounded bg-white p-3 shadow-sm"></div>
  </div>
</div>
<script>

function copyCalLink() {
  const copyText = document.getElementById("calLink");
  const btn = document.getElementById("copyBtn");
  const feedback = document.getElementById("copyFeedback");

  // Copy to clipboard
  navigator.clipboard.writeText(copyText.value).then(() => {
    // Show feedback
    feedback.classList.remove('d-none');
    btn.classList.replace('btn-outline-secondary', 'btn-success');
    
    // Reset after 3 seconds
    setTimeout(() => {
      feedback.classList.add('d-none');
      btn.classList.replace('btn-success', 'btn-outline-secondary');
    }, 3000);
  });
}

// Timezone detection
document.addEventListener('DOMContentLoaded', function() {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  document.getElementById('tz-display').textContent = tz.replace('_', ' ');
});

// Render the events in the ics on the page
document.addEventListener('DOMContentLoaded', function() {
  var calendarEl = document.getElementById('calendar');
  var calendar = new FullCalendar.Calendar(calendarEl, {
    initialView: 'listMonth',
    // This tells the calendar where to find your "Source of Truth"
    events: {
      url: 'community-call.ics', 
      format: 'ics'
    },
    themeSystem: 'bootstrap5'
  });
  calendar.render();
});
</script>
