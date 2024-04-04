# MariaDB 10.1 Docker Image (Galera) #

---

# Deprecation Notice #

This project is a proof of concept of running stateful applications on Kubernets/Docker Swarm written back in 2017 based on the following blog posts:

- https://severalnines.com/blog/running-galera-cluster-kubernetes/
- https://severalnines.com/blog/clustercontrol-and-galera-cluster-docker-swarm/
- https://severalnines.com/blog/swarm-mode-limitations-galera-cluster-production-setups/

This project aimed to provide a containerized solution for deploying MariaDB clusters using Galera replication. Over time, the project has served its purpose by showcasing the possibilities of containerization in database deployment scenarios.
                                                                                                                                                                                           However, with advancements in container orchestration technologies and best practices, such as Kubernetes Operators, the landscape of managing stateful workloads has evolved significantly. Kubernetes Operators offer a more robust and scalable approach to managing stateful applications in Kubernetes environments, providing automation, operational intelligence, and simplified management of complex applications like databases.

In light of these advancements, we recommend transitioning away from the Galera Docker MariaDB project and adopting Kubernetes Operators for managing MariaDB clusters in Kubernetes environments. Kubernetes Operators provide a more integrated and sustainable solution for deploying, managing, and scaling stateful workloads, including databases like MariaDB.

While the Galera Docker MariaDB project will no longer be actively maintained, the codebase will remain available on GitHub for reference purposes. We encourage users who are still leveraging this project to migrate to Kubernetes Operators for their MariaDB cluster management needs.

We appreciate your support and contributions to the Galera Docker MariaDB project over the years. As we look towards the future, we're excited about the possibilities that Kubernetes Operators bring to the table for managing stateful workloads in modern cloud-native environments.

---

## Table of Contents ##

1. [Overview](#overview)
2. [Requirement](#requirement)
3. [Image Description](#image-description)
4. [Run Container](#run-container)
5. [Build Image](#build-image)
6. [Discovery Service](#discovery-service)
7. [Known Limitations](#known-limitations)


## Overview ##

The image supports running MariaDB 10.1 (Galera is included) with Docker orchestration tool like Docker Engine Swarm Mode and Kubernetes and requires an etcd (standalone or cluster) to run homogeneously. It can also run on a standalone environment.

## Requirement ##

A healthy etcd cluster. Please refer to Severalnines' [blog post](http://severalnines.com/blog/mysql-docker-deploy-homogeneous-galera-cluster-etcd) on how to setup this.

## Image Description ##

To pull the image, simply:

```bash
$ docker pull severalnines/mariadb
```

The image consists of MariaDB 10.1 (Galera ready) and all of its components:
* MariaDB client package.
* Percona Xtrabackup.
* jq - Lightweight and flexible command-line JSON processor.
* report_status.sh - report Galera status to etcd every `TTL`.
* healthcheck.sh

## Run Container ##

The Docker image accepts the following parameters:

* One of `MYSQL_ROOT_PASSWORD` must be defined.
* The image will create the user `xtrabackup@localhost` for the XtraBackup SST method. If you want to use a password for the `xtrabackup` user, set `XTRABACKUP_PASSWORD`. 
* If you want to use the discovery service (right now only `etcd` is supported), set the address (ip:port format) to `DISCOVERY_SERVICE`. It can accept multiple addresses separated by a comma. The image will automatically find a running cluser by `CLUSTER_NAME` and join to the existing cluster (or start a new one).
* If you want to start without the discovery service, use the `CLUSTER_JOIN` variable. Empty variables will start a new cluster. To join an existing cluster, set `CLUSTER_JOIN` to the list of IP addresses running cluster nodes.
* `TTL` by default is 30 seconds. Container will report every `TTL - 2` seconds when it's alive (wsrep_cluster_state\_comment=Synced) via `report_status.sh`. If a container is down, it will no longer send an update to etcd thus the key (wsrep_cluster_state_comment) is removed after expiration. This simply indicates that the registered node is no longer synced with the cluster and it will be skipped when constructing the Galera communication address.

Minimum of 3 containers is recommended for high availability. Running standalone is also possible with standard "docker run" command as shown further down.


### Docker Engine Swarm Mode ###


#### Ephemeral Storage ####

Assuming:

* etcd cluster is running on 192.168.55.111:2379, 192.168.55.112:2379 and 192.168.55.113:2379.
* Created an overlay network called ``galera-net``.

Then, to run a three-node MariaDB Galera Cluster on Docker Swarm mode (with ephemeral storage):

```bash
$ docker service create \
--name mariadb-galera \
--replicas 3 \
-p 3306:3306 \
--network galera-net \
--env MYSQL_ROOT_PASSWORD=mypassword \
--env DISCOVERY_SERVICE=192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379 \
--env XTRABACKUP_PASSWORD=mypassword \
--env CLUSTER_NAME=my_wsrep_cluster \
severalnines/mariadb
```


#### Persistent Storage ####

Assuming:

* etcd cluster is running on 192.168.55.111:2379, 192.168.55.112:2379 and 192.168.55.113:2379.
* Created an overlay network called ``galera-net``.

Then, to run a three-node MariaDB Galera Cluster on Docker Swarm mode (with persistent storage):

```bash
$ docker service create \
--name mariadb-galera \
--replicas 3 \
-p 3306:3306 \
--network galera-net \
--mount type=volume,source=galera-vol,destination=/var/lib/mysql \
--env MYSQL_ROOT_PASSWORD=mypassword \
--env DISCOVERY_SERVICE=192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379 \
--env XTRABACKUP_PASSWORD=mypassword \
--env CLUSTER_NAME=my_wsrep_cluster \
severalnines/mariadb
```


#### Custom my.cnf ####

Assuming:

* Directory ``/mnt/docker/mysql-config`` is exist on all Docker host for data volume mapping. All custom `my.cnf` should be located under this directory.
* etcd cluster is running on 192.168.55.111:2379, 192.168.55.112:2379 and 192.168.55.113:2379.
* Created an overlay network called ``galera-net``.

Then, to run a three-node MariaDB Galera Cluster on Docker Swarm mode:

```bash
$ docker service create \
--name mariadb-galera \
--replicas 3 \
-p 3306:3306 \
--network galera-net \
--mount type=volume,source=galera-vol,destination=/var/lib/mysql \
--mount type=bind,src=/mnt/docker/mysql-config,dst=/etc/my.cnf.d \
--env MYSQL_ROOT_PASSWORD=mypassword \
--env DISCOVERY_SERVICE=192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379 \
--env XTRABACKUP_PASSWORD=mypassword \
--env CLUSTER_NAME=my_wsrep_cluster \
severalnines/mariadb
```

Verify with:

```
$ docker service ps mariadb-galera
```

External applications/clients can connect to any Docker host IP address or hostname on port 3306, requests will be load balanced between the Galera containers. The connection gets NATed to a Virtual IP address for each service "task" (container, in this case) using the Linux kernel's built-in load balancing functionality, IPVS. If the application containers reside in the same overlay network (galera-net), then use the assigned virtual IP address instead.

You can retrieve it using the inspect option:

```bash
$ docker service inspect mariadb-galera -f "{{ .Endpoint.VirtualIPs }}"
```

Or, simply ping to the service name inside one of the containers in the same network 'galera-net':

```bash
$ ping mariadb-galera
```


### Kubernetes ###

Coming soon.



### Without Orchestration Tool ###

To run a standalone Galera node, the command would be:

```bash
$ docker run -d \
-p 3306 \
--name=galera \
-e MYSQL_ROOT_PASSWORD=mypassword \
-e DISCOVERY_SERVICE=192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379 \
-e CLUSTER_NAME=my_wsrep_cluster \
-e XTRABACKUP_PASSWORD=mypassword \
severalnines/mariadb
```

With some iterations, you can create a three-node Galera cluster, as shown in the following example:

```bash
$ for i in 1 2 3; 
do \
docker run -d \
-p 3306 \
--name=galera${i} \
-e MYSQL_ROOT_PASSWORD=mypassword \
-e DISCOVERY_SERVICE=192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379 \
-e CLUSTER_NAME=my_wsrep_cluster \
-e XTRABACKUP_PASSWORD=mypassword \
severalnines/mariadb;
done
```

Verify with:

```bash
$ docker ps
```


## Build Image ##

To build Docker image, download the Docker related files available at [our Github repository](https://github.com/severalnines/galera-docker-mariadb101):

```bash
$ git clone https://github.com/severalnines/galera-docker-mariadb
$ cd galera-docker-mariadb
$ docker build -t --rm=true severalnines/mariadb .
```

Verify with:

```bash
$ docker images
```


## Discovery Service ##

All nodes should report to etcd periodically with an expiring key. The default `TTL` value is 30 seconds. Container will report every `TTL - 2` seconds when it's alive (wsrep_cluster_state\_comment=Synced) via `report_status.sh`. If a container is down, it will no longer send an update to etcd thus the key (wsrep_cluster_state_comment) is removed after expiration. This simply indicates that the registered node is no longer synced with the cluster and it will be skipped when constructing the Galera communication address.

To check the list of running nodes via etcd, run the following (assuming CLUSTER_NAME="my_wsrep_cluster"):

```javascript
$ curl -s "http://192.168.55.111:2379/v2/keys/galera/my_wsrep_cluster?recursive=true" | python -m json.tool
{
    "action": "get",
    "node": {
        "createdIndex": 10049,
        "dir": true,
        "key": "/galera/my_wsrep_cluster",
        "modifiedIndex": 10049,
        "nodes": [
            {
                "createdIndex": 10067,
                "dir": true,
                "key": "/galera/my_wsrep_cluster/10.255.0.6",
                "modifiedIndex": 10067,
                "nodes": [
                    {
                        "createdIndex": 10075,
                        "expiration": "2016-11-29T10:55:35.37622336Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.6/wsrep_last_committed",
                        "modifiedIndex": 10075,
                        "ttl": 10,
                        "value": "0"
                    },
                    {
                        "createdIndex": 10073,
                        "expiration": "2016-11-29T10:55:34.788170259Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.6/wsrep_local_state_comment",
                        "modifiedIndex": 10073,
                        "ttl": 10,
                        "value": "Synced"
                    }
                ]
            },
            {
                "createdIndex": 10049,
                "dir": true,
                "key": "/galera/my_wsrep_cluster/10.255.0.7",
                "modifiedIndex": 10049,
                "nodes": [
                    {
                        "createdIndex": 10049,
                        "key": "/galera/my_wsrep_cluster/10.255.0.7/ipaddress",
                        "modifiedIndex": 10049,
                        "value": "10.255.0.7"
                    },
                    {
                        "createdIndex": 10074,
                        "expiration": "2016-11-29T10:55:35.218496083Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.7/wsrep_last_committed",
                        "modifiedIndex": 10074,
                        "ttl": 10,
                        "value": "0"
                    },
                    {
                        "createdIndex": 10072,
                        "expiration": "2016-11-29T10:55:34.650574629Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.7/wsrep_local_state_comment",
                        "modifiedIndex": 10072,
                        "ttl": 10,
                        "value": "Synced"
                    }
                ]
            },
            {
                "createdIndex": 10070,
                "dir": true,
                "key": "/galera/my_wsrep_cluster/10.255.0.8",
                "modifiedIndex": 10070,
                "nodes": [
                    {
                        "createdIndex": 10077,
                        "expiration": "2016-11-29T10:55:39.681757381Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.8/wsrep_last_committed",
                        "modifiedIndex": 10077,
                        "ttl": 15,
                        "value": "0"
                    },
                    {
                        "createdIndex": 10076,
                        "expiration": "2016-11-29T10:55:38.638268679Z",
                        "key": "/galera/my_wsrep_cluster/10.255.0.8/wsrep_local_state_comment",
                        "modifiedIndex": 10076,
                        "ttl": 14,
                        "value": "Synced"
                    }
                ]
            }
        ]
    }
}
```


## Known Limitations ##

* The image are tested and built using Docker version 1.12.3, build 6b644ec on CentOS 7.1.

* There will be no automatic recovery if a split-brain happens (where all nodes are in Non-Primary state). This is because the MySQL service is still running, yet it will refuse to serve any data and will return error to the client. Docker has no capability to detect this since what it cares about is the foreground MySQL process which is not terminated, killed or stopped. Automating this process is risky, especially if the service discovery is co-located with the Docker host (etcd would also lose contact with other members). Although if the service discovery is healthy externally, it is probably unreachable from the Galera containers perspective, preventing each other to see the container’s status correctly during the glitch. In this case, you will need to intervene manually. Choose the most advanced node to bootstrap and then run the following command to promote the node as Primary (other nodes shall then rejoin automatically if the network recovers):

```bash
$ docker exec -it [container] mysql -uroot -pyoursecret -e 'set global wsrep_provider_options="pc.bootstrap=1"'
```

* Also, there is no automatic cleanup for the discovery service registry. You can remove all entries using either the following command (assuming the CLUSTER_NAME is my_wsrep_cluster):

```bash
$ curl http://192.168.55.111:2379/v2/keys/galera/my_wsrep_cluster?recursive=true -XDELETE
```

Or using etcdctl command:

```bash
$ etcdctl rm /galera/my_wsrep_cluster --recursive
```


## Deprecation Notice ##

This project is a proof of concept of running stateful applications on Kubernets/Docker Swarm written back in 2017 based on the following blog posts:

- https://severalnines.com/blog/running-galera-cluster-kubernetes/
- https://severalnines.com/blog/clustercontrol-and-galera-cluster-docker-swarm/
- https://severalnines.com/blog/swarm-mode-limitations-galera-cluster-production-setups/

This project aimed to provide a containerized solution for deploying MariaDB clusters using Galera replication. Over time, the project has served its purpose by showcasing the possibilities of containerization in database deployment scenarios.

However, with advancements in container orchestration technologies and best practices, such as Kubernetes Operators, the landscape of managing stateful workloads has evolved significantly. Kubernetes Operators offer a more robust and scalable approach to managing stateful applications in Kubernetes environments, providing automation, operational intelligence, and simplified management of complex applications like databases.

In light of these advancements, we recommend transitioning away from the Galera Docker MariaDB project and adopting Kubernetes Operators for managing MariaDB clusters in Kubernetes environments. Kubernetes Operators provide a more integrated and sustainable solution for deploying, managing, and scaling stateful workloads, including databases like MariaDB.

While the Galera Docker MariaDB project will no longer be actively maintained, the codebase will remain available on GitHub for reference purposes. We encourage users who are still leveraging this project to migrate to Kubernetes Operators for their MariaDB cluster management needs.

We appreciate your support and contributions to the Galera Docker MariaDB project over the years. As we look towards the future, we're excited about the possibilities that Kubernetes Operators bring to the table for managing stateful workloads in modern cloud-native environments.

