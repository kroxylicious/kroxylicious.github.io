---
layout: overview
title: Overview
permalink: /overview/
---

This page provides an overview of how Kroxylicious works.  For more details, please refer to the [documentation](./kroxylicious).

#### What is Kroxylicious?

Kroxylicious is an Apache Kafka&#174; protocol-aware proxy.  It can be used to layer uniform behaviours onto a
Kafka based system in areas such as data-governance, security, policy enforcement and audit without needing to
change either the applications or the Kafka Cluster.

Kroxylicious is a stand-alone component which is deployed between the applications that use Kafka and
the Kafka Cluster.  Instead of applications connecting straight to the Kafka Cluster, the applications connect to
Kroxylious which connects to the cluster on the application's behalf. In all other respects, introducing 
Kroxylicious into a Kafka system is transparant.

To adopt Kroxylicious, there are zero code changes required to the applications. There are no additional libraries to
install.  Kroxylicious supports applications written in any language supported by Kafka ecosystem (Java, Golang, Python,
Rust...).

On the Kafka Cluster side, there are no changes required either.  That is, no additional libraries to deploy or special
configurations to apply.  Kroxylicious works with *any* Kafka Cluster from a self-managed Kafka Cluster through to
a Kafka Service offered by a cloud provider.

A key concept in Kroxylicious is the Filter.  It is these that layer additional behaviours into the Kafka system.  

| ![image](../assets/overview.png){:width="100%"} |
|:-----------------------------------------------:|
|                   *Overview*                    |

##### Filters

The Filter is at the heart of Kroxylicious. Filters intercept [Kafka RPCs](https://kafka.apache.org/protocol.html)
as they travel through the proxy.  Filters can observe or transform the RPC, depending on the needs of the use-case. 
It is in this way that behaviours are introduced into the system.   Kroxylicious filters can act on the request RPCs, 
their response counterparts, or both.

Kroxylicious ships with some pre-built filters of its own (see [use-cases](../use-cases)). There is also the Filter API
that lets you build custom filters, to fit your own use-case.

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

##### Performance

Kroxylicious is careful to decode only the Kafka RPCs that the filters actually need to process. If no filter is
interested in a particular RPC, its bytes will pass straight through Kroxylicious.  This approach helps keep Kroxylicious
fast.

The actual performance overhead of using Kroxylicious depends on the particular use-case.

