# MariaDB Galera on Kubernetes #

YAML definitions to run MariaDB Galera Cluster 10.1 on Kubernetes with ReplicaSet or StatefulSet. Tested on Kubernetes v1.6 using ReplicaSet and StatefulSet.

## Deployment Steps ##

### 1. Deploy an etcd cluster ###

The image requires an etcd (standalone or cluster) for service discovery. Deploy an etcd cluster through Pod together with Service:

```bash
$ kubectl create -f etcd-cluster.yaml
```

### 2. Deploy the Galera Cluster ###

You can deploy using multiple ways, either ReplicaSet, DaemonSet or StatefulSet.

**ReplicaSet**

For ReplicaSet, use mariadb-rs.yml:

```bash
$ kubectl create -f mariadb-rs.yml
```

**StatefulSet**

For StatefulSet with persistent storage, start with creating the PVs and PVCs:

```bash
$ kubectl create -f mariadb-pv.yml
$ kubectl create -f mariadb-pvc.yml
```

Then, deploy the Galera Cluster pods:

```bash
$ kubectl create -f mariadb-ss.yml
```

Details at Severalnines' blog post.
