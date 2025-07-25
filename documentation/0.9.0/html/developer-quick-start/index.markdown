---
layout: quickstart
title: Developer quick start
version: 0.9.0
---

Kroxylicious' composable filter chains and pluggable API mean that you can write your own filters to apply your own rules to the Kafka protocol, using the Java programming language.

In this quick start you will build a custom filter and use it to modify messages being sent to/consumed from Kafka, learn about filter configuration and running custom filters, and find a starting point for developing your own custom filters with your own rules and logic.

# Getting started

## Prerequisites

To start developing your own custom filters for Kroxylicious, you will need to install [JDK 21](https://openjdk.org/projects/jdk/21/).

You'll also need to install the [Apache Maven CLI](https://maven.apache.org/index.html) and one of either [Podman](https://podman.io/docs/installation) or [Docker](https://docs.docker.com/install/) 
(Note that if you are using Podman, you may encounter issues with the integration tests. There are instructions [here](https://github.com/kroxylicious/kroxylicious/blob/main/DEV_GUIDE.md#running-integration-tests-on-podman) to resolve this).

## Get the code

The easiest way to learn how to build custom filters is with our `kroxylicious-sample` module, which contains some basic find-and-replace filters for you to experiment with.
Begin by downloading the latest `kroxylicious-sample` sources from the [Kroxylicious repository](https://github.com/kroxylicious/kroxylicious).

```shell
git clone https://github.com/kroxylicious/kroxylicious.git
```

# Build

Building the sample project is easy! You can build the `kroxylicious-sample` jar either on its own or with the rest of the Kroxylicious project.

To build all of Kroxylicious, including the sample:

```shell
mvn verify
```

Build with the `dist` profile for creating executable JARs:

```shell
mvn verify -Pdist -Dquick
```

# Run

Build both `kroxylicious-sample` and `kroxylicious-app` with the `dist` profile as above, then run the following command:

```shell
KROXYLICIOUS_CLASSPATH="kroxylicious-sample/target/*" kroxylicious-app/target/kroxylicious-app-{{ page.version }}-bin/kroxylicious-app-{{ page.version }}/bin/kroxylicious-start.sh --config kroxylicious-sample/sample-proxy-config.yml
```

# Configure

Filters can be added and removed by altering the `filters` list in the `sample-proxy-config.yml` file. 
You can also reconfigure the sample filters by changing the configuration values in this file.

The **SampleFetchResponseFilter** and **SampleProduceRequestFilter** each have two configuration values that must be specified for them to work:

- `findValue` - the string the filter will search for in the produce/fetch data
- `replacementValue` - the string the filter will replace the value above with

## Default Configuration

The default configuration for **SampleProduceRequestFilter** is:

```yaml
filters:
  - type: SampleProduceRequestFilterFactory
    config:
      findValue: foo
      replacementValue: bar
```

This means that it will search for the string `foo` in the produce data and replace all occurrences with the string `bar`. 
For example, if a Kafka Producer sent a produce request with data `{"myValue":"foo"}`, the filter would transform this into `{"myValue":"bar"}` and Kroxylicious would send that to the Kafka Broker instead.

The default configuration for **SampleFetchResponseFilter** is:

```yaml
filters:
  - type: SampleFetchResponseFilterFactory
    config:
      findValue: bar
      replacementValue: baz
```

This means that it will search for the string `bar` in the fetch data and replace all occurrences with the string `baz`. 
For example, if a Kafka Broker sent a fetch response with data `{"myValue":"bar"}`, the filter would transform this into `{"myValue":"baz"}` and Kroxylicious would send that to the Kafka Consumer instead.

# Modify

Now that you know how the sample filters work, you can start modifying them! Replace the `SampleFilterTransformer` logic with your own code, change which messages they apply to, or whatever else you like!
