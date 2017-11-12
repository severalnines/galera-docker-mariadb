# MariaDB Galera on Kubernetes #

YAML definitions to run MariaDB Galera Cluster 10.1 on Kubernetes. Tested on Kubernetes v1.6 using ReplicaSet and StatefulSet.

## Deployment Steps ##

### 1. Deploy an etcd cluster ###

The image requires an etcd (standalone or cluster) for service discovery. Deploy an etcd cluster with Pods and Services:

```bash
$ kubectl create -f etcd-cluster.yaml
```

### 2. Deploy the Galera Cluster ###

You can deploy the cluster with multiple ways - ReplicaSet (Deployment), DaemonSet or StatefulSet.

**ReplicaSet**

For ReplicaSet, use mariadb-rs.yml:

```bash
$ kubectl create -f mariadb-rs.yml
```

**StatefulSet**

If running on AWS ([kops](https://github.com/kubernetes/kops)), start by creating the storage class ```slow``` or ```standard```. It is possible if different peformance is desired to create a storage class of ones own choice. Please refer to [Kubernetes documentation on persistent disk](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#aws)  

```bash
$ kubectl create -f ./aws/storage-class-standard.yml
```
A Persistent Volume Claim doesn't need to be created and all that needs to be done is to uncomment the line with ```storageClassName``` specified. 

```yml
      storageClassName: standard
```

-OR-

If not utilizing a storage class on AWS, and with StatefulSet with persistent storage, start with creating the PVs and PVCs:

```bash
$ kubectl create -f mariadb-pv.yml
$ kubectl create -f mariadb-pvc.yml
```

Then, deploy the Galera Cluster pods:

```bash
$ kubectl create -f mariadb-ss.yml
```

Details at Severalnines' blog post.
