---
layout: post
title:  "Scaling for the Future: Evolving Kroxylicious Governance"
date:   2026-03-04 00:00:00 +0000
author: "Tom Bentley"
author_url: "https://github.com/tombentley"
categories: 
---

Hot on the heels of [the release of Kroxylicious 0.19.0](../2026-03-04-release-0_19_0/) we have some other news to share.
We are excited to announce a shift in how we manage the project, partly based on the proven model used by the Apache Software Foundation.

We’ve always believed that open-source success is built on transparency, community trust, and a shared vision. 
The project continues to evolve, and our governance model needs to change with it while ensuring the project remains truly vendor-neutral.

## Decoupling Roles: Introducing Committers and Project Managers

Previously, we relied on a flat "Code Owner" structure. 
While this worked well in the early days, we realised it was starting to make it harder to scale the project: 
In order to grow, we are going to need more people able to review and merge contributions. 
But those people might not always be interested, or able to make a commitment to helping ensure the project’s long term sustainability.

To solve this, we have split these duties into two distinct roles:
* **Committers** focus on code quality and technical output. 
  They have write access to our repositories and are responsible for reviewing and merging contributions.
* **Project Managers** (PMs) focus on the long-term health and sustainability of the project. 
  They manage the governance files, handle community elections, and ensure the project remains aligned with its goals and deal with our interactions with the CommonHaus foundation.

We hope that by decoupling these roles, we’ll be better able to scale our number of Committers to match our review volume without burdening them with administrative overhead. 
It creates a clearer pathway for contributors to take on leadership roles based on their interests, whether that’s deep technical work or project stewardship.

These changes are already reflected in our updated [`GOVERNANCE.md`](https://github.com/kroxylicious/.github/blob/main/GOVERNANCE.md).

## Moving Beyond `CODEOWNERS`

We are also moving away from using the GitHub `CODEOWNERS` file to enforce directory-level restrictions. 

We trust Committers to know the limits of their expertise and to pull in the right subject matter experts when a PR spans areas outside their immediate knowledge.
This reduces the friction of managing complex ownership files and avoids the pitfalls of stale ownership definitions that don't match the current team structure.

## Strengthening Our Organizational Memory

As we grow, we need to ensure that important technical decisions aren't lost in the temporary nature of our Slack channels.

While Slack remains our home for quick, day-to-day conversation, we’ve decided that mailing lists are the least worst way to share and record formal technical discussions and voting. 
This ensures that our decision-making process is archived, searchable, and – most importantly – publicly verifiable.

The `kroxylicious-dev` list will be our primary channel for development discussions, open to all contributors and committers.

* You can read and subscribe to the list on [google groups](https://groups.google.com/d/forum/kroxylicious-dev). 
* Alternatively, you can subscribe by sending an empty email to [kroxylicious-dev+subscribe@googlegroups.com](mailto:kroxylicious-dev+subscribe@googlegroups.com), 
* and unsubscribe by sending an empty email to [kroxylicious-dev+unsubscribe@googlegroups.com](mailto:kroxylicious-dev+unsubscribe@googlegroups.com)

The project managers will use a private list, but only for communication that needs to remain private. 
You can contact them by email to [kroxylicious-pms@googlegroups.com](mailto:kroxylicious-pms@googlegroups.com).

## Building Community Connection

Governance isn't just about documents and voting; it’s about people. 
We want to ensure that our contributors feel connected to the project's direction and to each other.

To facilitate more direct and synchronous collaboration, we are launching a regular Community Call that anyone can join. 

The Kroxylicious community is spread around the world, and we want to be as inclusive as possible. 
In particular, we didn't want the meeting to always be in the middle of the night for someone in an unfortunate timezone. 
To support this, while the meeting cadence is every two weeks, the meeting time will alternate by ±12 hours every other call. 
But timezones and daylight savings time makes it a bit tricky to describe in a blog post.

You can see the time of upcoming meetings [on the website](https://kroxylicious.io/join-us/community-call/), and add the meeting schedule to your calendar app.

## What’s Next?

We’re excited to continue building Kroxylicious in an environment that is open, inclusive, and built to last. 
Check out the updated docs and let us know what you think!


