---
layout: index
title: Overview
permalink: /overview/
---

This page provides an overview of how Kroxylicious works.  For more details, please refer to the [documentation](./kroxylicious).

#### What is Kroxylicious?

Kroxylicious is an Apache Kafka&#174; protocol-aware proxy.  It can be used to layer uniform behaviours onto a
Kafka based system in areas such as data-governance, security, policy enforcement and audit without needing to
change either the applications or the Kafka Cluster.

##### Filters

The Filter is at the heart of Kroxylicious. Filters intercept [Kafka RPCs](https://kafka.apache.org/protocol.html)
as they travel through the proxy.  Filters can observe or transform the RPC, depending on the needs of the  use-case. 
It is in this way that behaviours are introduced into the system.   Kroxylicious filters can act on the request RPCs, 
their response counterparts, or both.

Kroxylicious ships with some pre-built filters of its own (see [use-cases](../use-cases)). There is also the Filter API
that lets you build your own filters, tailored to your use-case.

| ![image](../assets/filter.png){:width="100%"} |
|:---------------------------------------------:|
|         *Request/Response Filtering*          |


##### Filter Chains

Filters are composable, meaning you can chain filters together to build complex behaviours from simpler units.

For example, you may choose to build a filter chain compromising a policy enforcement filter together with an
audit filter to suit the requirements of your use-case.


| ![image](../assets/filter-chain.png){:width="100%"} |
|:----------------------------------------------------:|
|                   *Filter Chains*                    |

##### Deployment

Kroxylicious is deployed interposed between the applications and the Kafka Cluster.

To introduce Kroxylicious, it is necessary to change the application's `bootstrap.servers` property
to point at a bootstrap endpoint exposed by Kroxylicious.  Kroxylicious's configuration points it at
the Kafka Cluster being proxied.

Kroxylicious automatically adapts to the topology of the Kafka Cluster being proxied and exposes
proxied broker endpoints for each individual broker of the Kafka Cluster.

The precise way in which Kroxylicious present itself on the network is configurable.


