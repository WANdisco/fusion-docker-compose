# WANdisco Fusion

## Overview

This repository contains a docker-compose configuration that can be used to deploy a fully functional version of WANdisco Fusion with a 30 day evaluation license:

- HDP Sandbox to ADLS Gen2, Live Hive and Databricks integration

Full documentation for this case can be found in our [Quickstart Guide](https://wandisco.github.io/wandisco-documentation/docs/quickstarts/hdp_sandbox_lhv_client-adlsg2_lan)

## Prerequisites
1. [Docker](https://docs.docker.com/install/overview/) and [Docker Compose](https://docs.docker.com/compose/install/) installed on a suitable host

## Installation Process
There are a series of steps that must be completed in order to properly deploy and leverage WANdisco Fusion:

1. [Download](https://github.com/WANdisco/hdp-adls2/archive/master.zip) and unzip or git clone the configuration files.

1. Start the cluster(s) with:

```bash
docker-compose up -d
```

## Usage
To interact with the Docker Compose stack, ensure you are in the same directory as the `docker-compose` configuration files.

Then, to deploy the containers:
```bash
docker-compose up -d
```

To bring down the containers:
```bash
docker-compose down
```

To view the status of the deployed containers and port allocations:
```bash
docker-compose ps
```
</br>

> Note: The Docker managed volumes persist between container restarts. This ensures that any configuration and database changes are kept once you get up and running. You can remove them if you want to wipe out changes made _after_ initial launch, resetting the volumes, by running `docker-compose down -v`.

### UI Access
Fusion UI is available at http://docker_host:8081

## License
This repository is Apache 2.0 licensed. Please see `./LICENSE` for more information.

Images provided through Dockerhub are offered for evaluation purposes. By pulling these images, you agree you have read, understood and accept the [WANdisco EULA](https://www.wandisco.com/eula).

Contact sales@wandisco.com for other distros and licensing.
