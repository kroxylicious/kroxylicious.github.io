---
layout: post
title:  "kroxylicious-junit5-extension release 0.9.1"
date:   2024-11-07 00:00:00 +0000
author: "Grace Grimwood"
author_url: "https://github.com/gracegrimwood"
categories:  releases junit5-extension
---

The Kroxylicious project is very pleased to announce the [0.9.1](https://github.com/kroxylicious/kroxylicious-junit5-extension/releases/tag/v0.9.1) release of our Junit5 Extension. This release contains minor improvements, bugfixes, and dependency upgrades.

### Fixes and Improvements in 0.9.1

* [@k-wall](https://www.github.com/k-wall) found and fixed an issue where tracking of Kafka brokers was not thread-safe which caused intermittent failures (**[#379](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/379)**)

### Dependency Changes in 0.9.1

* Byte Buddy 1.14 removed (**[#373](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/373)**)
* Apache Kafka upgraded from 3.7.1 to 3.8.0 (**[#365](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/365)**)
* Testcontainers upgraded from 1.19.8 to 1.20.1 (**[#362](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/362)**, **[#366](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/366)**, **[#402](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/402)**, **[#411](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/411)**)
* Mockito upgraded from 5.12.0 to 5.14.2 (**[#381](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/381)**, **[#395](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/395)**, **[#401](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/401)**, **[#403](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/403)**)
* Log4J upgraded from 2.23.1 to 2.24.1 (**[#388](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/388)**, **[#393](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/393)**)
* JUnit upgraded from 5.10.3 to 5.11.3 (**[#369](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/369)**, **[#392](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/392)**, **[#398](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/398)**, **[#405](https://github.com/kroxylicious/kroxylicious-junit5-extension/pull/405)**)

### Feedback

Please let us know, through [Slack](https://kroxylicious.slack.com) or [GitHub](https://github.com/kroxylicious/kroxylicious-junit5-extension/issues), if you find the extension interesting or helpful.
