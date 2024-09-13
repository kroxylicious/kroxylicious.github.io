---
layout: post
title:  "Moving Kroxylicious Junit5 Extension to Kafka 4.0"
date:   2024-09-13 00:00:00 +0000
author: "Keith Wall"
author_url: "https://www.github.com/k-wall"
categories:  [junit5, kroxylicious, kafka4]
---

Are you using the [kroxylicuous-junit5-extension](https://github.com/kroxylicious/kroxylicious-junit5-extension) to inject Kafka clusters into your integration tests?   With Apache Kafka approaching the 4.0 milestone, we
are looking for input to help decide the best way to manage the move to Kafka 4.0.

Kafka 4.0 will will remove support for Zookeeper managed clusters.  The Extension is currently capable of producing clusters managed by KRaft or Zookeeper, using
whatever Kafka version you provide to it on the classpath.  With Kafka 4.0's arrival the possibility of a Zookeeper managed cluster goes away.

How important it is to you that the Extension continues to support the production of Kafka clusters managed by Zookeper when _Kafka 3.x_ is on the classpath?  Talk to us on this issue [#389](https://github.com/kroxylicious/kroxylicious-junit5-extension/issues/389).
