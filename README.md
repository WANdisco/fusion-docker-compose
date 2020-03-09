# WANdisco Fusion 

## Overview

This repository contains a tool (setup-env.sh) which build a docker-compose configuration that can be used to deploy a fully functional version of WANdisco Fusion with a 30 day evaluation license. Fusion supports Live Migration or active-active replication of files stored in any of the following: 

- Azure - ADLS Gen 1, ADLS Gen 2, WASB, HDInsights 
- AWS S3/EMRFS
- Google Cloud*
- Hadoop - CDH 
- Hadoop - HDP
- Hadoop - Apache (Unmanaged)*
- Alibaba OSS / EMR
- MAPR*
- Local File System*

*Available in container images but may not yet be configurable via the setup script. 

The stack can be used for standalone operation across two storage zones on a single host, or as a single zone to connect with a remote Fusion deployment.  

The ./setup-env.sh script lets you select the desired platform and configure storage before staring Fusion by running docker-compose up -d. 

## Prerequisites 
1. [Docker](https://docs.docker.com/install/overview/) and [Docker Compose](https://docs.docker.com/compose/install/) installed on a suitable host

## Installation Process
There are a series of steps that must be completed in order to properly deploy and leverage WANdisco Fusion:

1. [Download](https://github.com/WANdisco/fusion-docker-compose/archive/master.zip) and unzip or git clone the configuration files. 

1. Run `./setup-env.sh` and follow the prompts

1. Start the cluster(s) with:

```bash
docker-compose up -d
```

### Modifying The Configuration
Configuration can be changed in the following files:

- common.env
- zone_a.env
- zone_b.env (when a second zone has been configured)

If you make changes to these files, run `./setup-env.sh` and they will be applied to the docker compose files.

## Usage
To interact with the Docker Compose stack, ensure you are in the same directory as the `docker-compose.yml`. 

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

### SSH Access
SSH is configured on ports 2022 and 2522 on Hadoop and Cloudera zone types to allow remote configuration. The key for remote access to these ssh instances is available in the container logs:

```bash
# get the container names for the sshd servers
docker-compose ps
# extract the key, replace with container name from above
docker logs compose_sshd-hdp_1 
# after writing to a secure pem file, test remote access
ssh -i cdh-key.pem -p 2022 root@docker_host
```

This ssh instance only makes selected files available to the fusion server via the /etc/sshd_exports volume mount. Any other changes are isolated to the container.

## HDP Sandbox to ADLS Gen2 with Databricks

There is also the option to create a sandboxed Hortonworks HDP cluster preconfigured to replicate Hive data in to Azure Databricks.

Full documentation for this option can be found in our [Quickstart Guide](https://wandisco.github.io/wandisco-documentation/docs/quickstarts/hdp_sandbox_lhv_client-adlsg2_lan)

## License
This repository is Apache 2.0 licensed. Please see `./LICENSE` for more information.

Images provided through Dockerhub are offered for evaluation purposes. By pulling these images, you agree you have read, understood and accept the [WANdisco EULA](https://www.wandisco.com/eula).

Contact sales@wandisco.com for other distros and licensing. 
