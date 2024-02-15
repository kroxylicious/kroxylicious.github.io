---
htmlid: deploy
tab_title: Deployment
---
Kroxylicious is a Java application based on [Netty](https://netty.io/), which means it will run anywhere you can run a JVM. (That's a lot of places!)
To help you get started with Kroxylicious, we've created this quick setup guide.

<br />

# Getting started

### Prerequisites

#### Java

To get started deploying Kroxylicious, you will need to install a Java Runtime Environment (JRE) with minimum version 17. This does not come included with Kroxylicious.

Some operating systems come with a JRE already installed. You can check what Java version you have installed by running the following command:

```shell
java -version
```

{% capture jre_note %}
If you get an error or the command doesn't return anything, you may not have a JRE installed, or your JRE may not have been correctly added to your system's `PATH` variable.
{% endcapture %}

{% include bs-alert.html type="primary" icon="info-circle-fill" content=jre_note %}

#### Apache Kafka&#174;

You will also need a running Apache Kafka&#174; cluster for Kroxylicious to proxy. The official Apache Kafka&#174; [quickstart](https://kafka.apache.org/documentation/#quickstart) has instructions for setting up a local bare metal cluster.

Once your cluster is set up, the cluster bootstrap address used by Kroxylicious can be changed in the configuration YAML file (see the [**Configure**](#configure) section below).

<br />

### Downloading Kroxylicious

Kroxylicious can be downloaded from the [releases](https://github.com/kroxylicious/kroxylicious/releases) page of the Kroxylicious GitHub repository, or from Maven Central.

In GitHub, all releases since v0.4.0 have an attached `kroxylicious-app-*-bin.zip` file. Download the latest version of this zip, and optionally verify the contents of the package with the attached `kroxylicious-app-*-bin.zip.asc` file.

{% capture os_archive_note %}
If you're trying Kroxylicious out on Linux or macOS, you may find the `.tar.gz` format easier to work with. We're using the `.zip` files in this quickstart for cross-platform compatibility, but we recommend you use whichever format you're most familiar with.
{% endcapture %}

{% include bs-alert.html type="primary" icon="info-circle-fill" content=os_archive_note %}

<br />

# Install

Extract the downloaded Kroxylicious Zip file into the directory you would like to install Kroxylicious in.
Ensure the `kroxylicious-start.sh` and `run-java.sh` files in the `bin/` directory within the extracted folder have at least read and execute (`r-x`) permissions for the owner.

<br />

# Configure

Kroxylicious is configured with YAML. An example configuration file can be found in the `config/` directory of the extracted Kroxylicious folder, which you can either modify or use as reference for creating your own configuration file.

From the configuration file you can specify how Kroxylicious presents each Apache Kafka&#174; broker to clients, where Kroxylicious will locate the Apache Kafka&#174; cluster(s) to be proxied, and which filters Kroxylicious should use along with any configuration for those filters.

For this quickstart we will use Kroxylicious in Port-Per-Broker configuration, and assume that both your Apache Kafka&#174; cluster and clients are running on your local machine and using their default configuration. This means we can use the example proxy config file that comes with Kroxylicious.

{% capture kroxylicious_config_note %}
If your machine uses a non-standard port configuration, or if you have used custom settings for your Apache Kafka&#174; cluster (or if your cluster is running on a different machine) you will need to adjust your Kroxylicious configuration accordingly. More information about configuring Kroxylicious can be found in the [documentation](https://kroxylicious.io/kroxylicious/#_deploying_proxies).
{% endcapture %}

{% include bs-alert.html type="primary" icon="info-circle-fill" content=kroxylicious_config_note %}

<br />

# Run

From within the extracted Kroxylicious folder, run the following command:

```shell
./bin/kroxylicious-start.sh --config config/example-proxy-config.yml
```

To use your own configuration file instead of the example, just replace the file path after `--config`.

<br />

# Use

To use your Kroxylicious proxy, your client(s) will need to point to the proxy (using the configured address) rather than directly at the Apache Kafka&#174; cluster.

Here's how you would use Kroxylicious with the console producer and console consumer:

```shell
# In each command below, substitute $KROXYLICIOUS_BOOTSTRAP for the bootstrap address of your Kroxylicious instance.

# create a topic "my_topic" via Kroxylicious
bin/kafka-topics.sh --create --topic my_topic --bootstrap-server $KROXYLICIOUS_BOOTSTRAP

# produce the string "hello world" to your topic via Kroxylicious
echo "hello world" | bin/kafka-console-producer.sh --topic my_topic --bootstrap-server $KROXYLICIOUS_BOOTSTRAP

# Consume your string from your topic via Kroxylicious
bin/kafka-console-consumer.sh --topic my_topic --from-beginning --bootstrap-server $KROXYLICIOUS_BOOTSTRAP
```

Here's how you would use Kroxylicious with a command line client like [Kaf](https://github.com/birdayz/kaf):

```shell
# In each command below, substitute $KROXYLICIOUS_BOOTSTRAP for the bootstrap address of your Kroxylicious instance.

# create a topic "my_topic" via Kroxylicious
kaf -b $KROXYLICIOUS_BOOTSTRAP topic create my_topic

# produce the string "hello world" to your topic via Kroxylicious
echo "hello world" | kaf -b $KROXYLICIOUS_BOOTSTRAP produce my_topic

# Consume your string from your topic via Kroxylicious
kaf -b $KROXYLICIOUS_BOOTSTRAP consume my_topic
```
