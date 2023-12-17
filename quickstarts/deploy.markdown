Kroxylicious is a Java application based on [Netty](https://netty.io/), which means it will run anywhere you can run a JVM. (That's a lot of places!)
To keep things simple, we've created a quick setup guide to help.

<br />

## Getting started

#### Prerequisites

To get started deploying Kroxylicious, you will need to install a Java Runtime Environment (JRE) with minimum version 17. This does not come included with the Kroxylicious JAR files.

Some operating systems come with a JRE already installed. You can check what Java version you have installed by running the following command:

```shell
java -version
```

If you get an error or the command doesn't return anything, you may not have a JRE installed, or your JRE may not have been correctly added to your system's `PATH` variable.

<br />

#### Downloading Kroxylicious

Kroxylicious can be downloaded from the [releases](https://github.com/kroxylicious/kroxylicious/releases) page of the Kroxylicious GitHub repository, or from Maven Central.

In GitHub, all releases since v0.4.0 have an attached `kroxylicious-app-*-bin.zip` file. Download this, and optionally verify the contents of the package with the attached `kroxylicious-app-*-bin.zip.asc` file.

<br />

## Install and Run

#### Installing Kroxylicious

Extract the downloaded Kroxylicious Zip file into the directory you would like to install Kroxylicious in. Ensure the `kroxylicious-start.sh` and `run-java.sh` files in the `bin/` directory within the extracted folder have at least read, write, and execute (`rwx`) permissions for the owner.

<br />

#### Configuring Kroxylicious

Kroxylicious is configured with YAML. An example configuration file can be found in the `config/` directory of the extracted Kroxylicious folder, which you can either modify or use as reference for creating your own configuration file.

From the configuration file you can specify how Kroxylicious presents each Kafka broker to the Kafka clients, as well as which filters Kroxylicious should use and any configuration for those filters.

<br />

#### Running Kroxylicious

From within the extracted Kroxylicious folder, run the following command:

```shell
./bin/kroxylicious-start.sh --config config/example-proxy-config.yml
```

To use your own configuration file instead of the example, just replace the file path after `--config`.