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
       You don't need an account to join. 
       </p>
       <div class="alert alert-warning" role="alert">
         <h4 class="alert-heading">Meetings are public (and recorded!)</h4>
         <p>Meetings are recorded and shared on our youtube channel.</p>
       </div>
       <p>If your browser knows about your calendar app you should be able to subscribe in your calendar app by clicking the button below.</p>
       <div><a href="webcal://{{ site.hostname }}/join-us/community-call/community-call.ics" class="btn btn-primary">Subscribe</a></div>
     </div>
     <div>
       <h2>Upcoming events</h2>
       <div>Times are shown in your browser's local timezone, <span id="tz-display"></span>.</div>
      <div id="calendar"/>
  </div>
</div>
<script>
    document.addEventListener('DOMContentLoaded', function() {
      const userTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      document.getElementById('tz-display').textContent = userTimeZone;
    
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
