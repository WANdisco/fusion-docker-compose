# WANdisco Fusion 

## Overview
This repository contains a Docker Compose stack that deploys the WANdisco Fusion platform. The stack is designed for operation in two zones. The _first_ zone should be configured for the Hortonworks Data Platform ([HDP](https://hortonworks.com/products/data-platforms/hdp/)) on Hadoop, while the _second_ zone will be configured for [Azure Data Lake Storage Gen2](https://docs.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction). 

## Prerequisites 
1. [Docker](https://docs.docker.com/install/overview/) and [Docker Compose](https://docs.docker.com/compose/install/) installed on a suitable host
1. Hortonworks HDP 2.6.5 Cluster or Sandbox 
1. Azure ADLS Gen 2 account details (Tenant ID, Client ID, Client secret) 

## Installation Process
There are a series of steps that must be completed in order to properly deploy and leverage WANdisco Fusion:

1. [Download](https://github.com/WANdisco/fusion-docker-compose/archive/master.zip), unzip and modify the configuration files under `fusion-shared-a` and `fusion-shared-b`

1. Ensure the desired WANdisco license is available at `./fusion-common/license.key`(An evaluation license is provided)

### Modifying The Configuration
In zone 1, there is Hadoop specific and WANdisco Fusion specific config that must be specified. This config is defined as follows under `fusion-shared-a`:
- `stage/etc/hadoop/2.6.5.0-292/0/` : contains the Hadoop cluster configuration
- `stage/etc/wandisco/fusion/ihc/server/hdp-2.6.5` : contains configuration specific to the Fusion IHC Server component in zone 1
- `stage/etc/wandisco/fusion/server` : contains configuration specific to the main Fusion Server application component in zone 1
- `stage/opt/wandisco/fusion-ui-server/properties` : contains configuration specific to the Fusion UI Server component in zone 1

In zone 2, there is no Hadoop config, as it is configured for the Azure platform. The config is defined for zone 2 under `fusion-shared-b` as:
- `/etc/wandisco/fusion/ihc/server/hdi-3.6` : contains configuration specific to the Fusion IHC Server component in zone 2
- `/etc/wandisco/fusion/server/` : contains configuration specific to the main Fusion Server application component in zone 2
- `stage/opt/wandisco/fusion-ui-server/properties` : contains configuration specific to the Fusion UI Server component in zone 2

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

> Note: The Docker managed volumes persist between container restarts. This ensures that any configuration and database changes are kept once you get up and running. You can remove them if you want to wipe out changes made _after_ initial launch, resetting the volumes. To remove them specify the `-v` flag to `docker-compose down`. 

### UI Access 
Fusion UI is available at http://localhost:8083 for HDP Zone and http://localhost:8583 for ADLS Gen2, with username and password admin/admin.


### Ensure The Proper License Is Being Used
By default, this repository contains a trial license key for trying out the WANdisco FUsion platform. Once the software is purchased, this license can be swapped out with the license for your copy by replacing the file at `./fusion-common/license.key`. 

## License
This repository is Apache 2.0 licensed. Please see `./LICENSE` for more information.

Images provided through Dockerhub are offered for evaluation purposes. By pulling these images, you agree you have read, understood and accept the [WANdisco EULA](https://www.wandisco.com/eula).
