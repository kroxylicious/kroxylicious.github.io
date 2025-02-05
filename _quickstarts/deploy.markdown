---
htmlid: deploy
tab_title: Deployment
---
Kroxylicious is a Java application based on [Netty](https://netty.io/), which means it will run anywhere you can run a JVM. (That's a lot of places!)
To help you get started with Kroxylicious, we've created this quick setup guide.

<br />

<h1 id="getting-started-deployment">Getting started</h1>

<h2 class="fs-3" id="prerequisites-deployment">Prerequisites</h2>

<h3 class="fs-4" id="java-deployment">Java</h3>

To get started deploying Kroxylicious, you will need to install a Java Runtime Environment (JRE) with minimum version 17. This does not come included with Kroxylicious.

Some operating systems come with a JRE already installed. You can check what Java version you have installed by running the following command:

```shell
java -version
```

{% capture jre_note %}
If you get an error or the command doesn't return anything, you may not have a JRE installed, or your JRE may not have been correctly added to your system's `PATH` variable.
{% endcapture %}

{% include bs-alert.html type="primary" icon="info-circle-fill" content=jre_note %}

<h3 class="fs-4" id="apache-kafka-deployment">Apache Kafka&#174;</h3>

You will also need a running Apache Kafka&#174; cluster for Kroxylicious to proxy. The official Apache Kafka&#174; [quickstart](https://kafka.apache.org/documentation/#quickstart) has instructions for setting up a local bare metal cluster.

Once your cluster is set up, the cluster bootstrap address used by Kroxylicious can be changed in the configuration YAML file (see the [**Configure**](#configure-deployment) section below).

<br />

<h2 class="fs-3" id="downloading-kroxylicious-deployment">Downloading Kroxylicious</h2>

Kroxylicious can be downloaded from the [releases](https://github.com/kroxylicious/kroxylicious/releases) page of the Kroxylicious GitHub repository, or from Maven Central.

In GitHub, all releases since v0.4.0 have an attached `kroxylicious-app-*-bin.zip` file. Download the latest version of this zip, and optionally verify the contents of the package with the attached `kroxylicious-app-*-bin.zip.asc` file.

{% capture os_archive_note %}
If you're trying Kroxylicious out on Linux or macOS, you may find the `.tar.gz` format easier to work with. We're using the `.zip` files in this quickstart for cross-platform compatibility, but we recommend you use whichever format you're most familiar with.
{% endcapture %}

{% include bs-alert.html type="primary" icon="info-circle-fill" content=os_archive_note %}

<br />

<h1 id="install-deployment">Install</h1>

Extract the downloaded Kroxylicious Zip file into the directory you would like to install Kroxylicious in.
Ensure the `kroxylicious-start.sh` and `run-java.sh` files in the `bin/` directory within the extracted folder have at least read and execute (`r-x`) permissions for the owner.

<br />

<h1 id="configure-deployment">Configure</h1>

Kroxylicious is configured with YAML. From the configuration file you can specify how Kroxylicious presents each Apache Kafka&#174; broker to clients, where Kroxylicious will locate the Apache Kafka&#174; cluster(s) to be proxied, and which filters Kroxylicious should use along with any configuration for those filters.

An example configuration file can be found in the `config/` directory of the extracted Kroxylicious folder, which you can either modify or use as reference for creating your own configuration file.

For this quickstart we will use Kroxylicious in Port-Per-Broker configuration, and assume that both your Apache Kafka&#174; cluster and clients are running on your local machine and using their default configuration. This means we can use the example proxy config file that comes with Kroxylicious.

If your machine uses a non-standard port configuration, or if you have used custom settings for your Apache Kafka&#174; cluster (or if your cluster is running on a different machine) you will need to adjust your Kroxylicious configuration accordingly. More information about configuring Kroxylicious can be found in the [documentation](https://kroxylicious.io/kroxylicious/#_deploying_proxies).

<br />

<h1 id="run-deployment">Run</h1>

From within the extracted Kroxylicious folder, run the following command:

```shell
./bin/kroxylicious-start.sh --config config/example-proxy-config.yml
```

To use your own configuration file instead of the example, just replace the file path after `--config`.

<br />

<h1 id="use-deployment">Use</h1>

To use your Kroxylicious proxy, your client(s) will need to point to the proxy (using the configured address) rather than directly at the Apache Kafka&#174; cluster.

[//]: # (====================================================================)
[//]: # (START - Use Section Examples Tabbed Card)
[//]: # (====================================================================)

[//]: # (The element ID for this nested tabbed card, used for everything that makes nesting cards and having tabs work)
[//]: # (We prepend the ID of the parent card tab - i.e. this file - to this element ID to ensure it is unique)
{% capture use_examples_htmlid %}{{ page.htmlid }}-useExamples{% endcapture %}

{% capture apacheClientContent %}
In each command below, substitute `$KROXYLICIOUS_BOOTSTRAP` for the bootstrap address of your Kroxylicious instance.

<br />

<h2 class="fs-5">1. Create a topic via Kroxylicious</h2>
Create a topic called "my_topic" using the `kafka-topics.sh` command line client:
```shell
bin/kafka-topics.sh --create --topic my_topic --bootstrap-server $KROXYLICIOUS_BOOTSTRAP
```

<br />

<h2 class="fs-5">2. Produce a string to your topic via Kroxylicious</h2>
Produce the string "hello world" to your new topic using the `kafka-console-producer.sh` command line client:
```shell
echo "hello world" | bin/kafka-console-producer.sh --topic my_topic --bootstrap-server $KROXYLICIOUS_BOOTSTRAP
```

<br />

<h2 class="fs-5">3. Consume your string from your topic via Kroxylicious</h2>
Consume your string ("hello world") from your topic ("my_topic") using the `kafka-console-consumer.sh` command line client:
```shell
bin/kafka-console-consumer.sh --topic my_topic --from-beginning --bootstrap-server $KROXYLICIOUS_BOOTSTRAP
```
{% endcapture %}

{% capture kafClientContent %}
In each command below, substitute `$KROXYLICIOUS_BOOTSTRAP` for the bootstrap address of your Kroxylicious instance.

<br />

<h2 class="fs-5">1. Create a topic with Kaf via Kroxylicious</h2>
Create a topic called "my_topic" using Kaf:
```shell
kaf -b $KROXYLICIOUS_BOOTSTRAP topic create my_topic
```

<br />

<h2 class="fs-5">2. Produce a string to your topic with Kaf via Kroxylicious</h2>
Produce the string "hello world" to your new topic:
```shell
echo "hello world" | kaf -b $KROXYLICIOUS_BOOTSTRAP produce my_topic
```

<br />

<h2 class="fs-5">3. Consume your string from your topic with Kaf via Kroxylicious</h2>
Consume your string ("hello world") from your topic ("my_topic"):
```shell
kaf -b $KROXYLICIOUS_BOOTSTRAP consume my_topic
```
{% endcapture %}

[//]: # (These IDs need to be identical across the tab elements and the tab content elements, so we declare them here to avoid confusion)
[//]: # (We prepend the ID of the parent element to these IDs to ensure they are unique)
{% capture apache_htmlid %}{{use_examples_htmlid}}-apacheClient{% endcapture %}
{% capture kaf_htmlid %}{{use_examples_htmlid}}-kafClient{% endcapture %}

{% capture use_example_tabs %}
{% include nested-card-tabbed/tab.html htmlid=apache_htmlid is_active_tab=true tab_title="Using Kroxylicious with the Apache Kafka&#174; command line clients" %}
{% include nested-card-tabbed/tab.html htmlid=kaf_htmlid is_active_tab=false tab_title="Using Kroxylicious with the [Kaf](https://github.com/birdayz/kaf) command line client" %}
{% endcapture %}

{% capture use_example_content %}
{% include nested-card-tabbed/tab-content.html htmlid=apache_htmlid tabindex=0 is_active_tab=true content=apacheClientContent %}
{% include nested-card-tabbed/tab-content.html htmlid=kaf_htmlid tabindex=1 is_active_tab=false content=kafClientContent %}
{% endcapture %}

{% include nested-card-tabbed/card.html htmlid=use_examples_htmlid tabs=use_example_tabs content=use_example_content %}

[//]: # (====================================================================)
[//]: # (END - Use Section Examples Tabbed Card)
[//]: # (====================================================================)
