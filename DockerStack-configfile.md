# **Comprehensive Guide for the Docker Swarm-based Graylog Cluster Deployment**

This guide explains the key components, relationships, and configurations of the services deployed in the Graylog cluster, managed by Docker Swarm. Each section describes the purpose of the components, parameters, and their relationships.

---

## **1. Network Configuration**
- **Network `gl-swarm-net`**: 
  - Defined as an **external** network to connect all services in the stack. 
  - It ensures that all services, including MongoDB, OpenSearch, Graylog, and Traefik, communicate seamlessly within the Docker Swarm environment.

---

## **2. Volume Configuration**
The volumes are **bind mounts** that use GlusterFS paths for persistent storage across multiple nodes.  
Each service (MongoDB, OpenSearch, Graylog) has dedicated directories to store its data persistently.

| **Service**         | **Volume Path**                        | **Mounted Path** in Container           |
|----------------------|----------------------------------------|----------------------------------------|
| **MongoDB**         | `/home/admin/mnt-glusterfs/mongodb/`   | `/data/db`                             |
| **OpenSearch**      | `/home/admin/mnt-glusterfs/opensearch/`| `/usr/share/opensearch/data`           |
| **Graylog**         | `/home/admin/mnt-glusterfs/graylog/`   | `/usr/share/graylog/data`              |
| **Traefik**         | `/home/admin/mnt-glusterfs/traefik/certs/` | `/certs/`                            |

**Key Points**:
- **GlusterFS** ensures distributed and fault-tolerant storage for these bind-mounted volumes.
- MongoDB uses multiple data directories (`mongo01-data`, etc.) for each replica set node.
- OpenSearch and Graylog use individual data directories to isolate their storage.

---

## **3. MongoDB Configuration**
MongoDB forms the **primary database** backend for Graylog.  
Three MongoDB nodes are deployed as part of a **replica set** to ensure high availability.

### **Nodes**:
- **`mongodb01`**, **`mongodb02`**, and **`mongodb03`**.
- Each node runs on a dedicated port: `27017`, `27018`, and `27019`.

### **Commands**:
- The `mongod` process is started with the replica set option `--replSet dbrs`.
- The script `init-replset.js` initializes the MongoDB replica set.

### **Relationships**:
- MongoDB nodes interact with **Graylog** as the primary storage for configurations, logs, and metadata.

---

## **4. OpenSearch Configuration**
OpenSearch serves as the **data storage and search engine** for Graylog.

### **Nodes**:
- **`opensearch01`**, **`opensearch02`**, and **`opensearch03`**.
- Each node is published on dedicated ports: `9201`, `9202`, and `9203`.

### **Parameters**:
- **Cluster Name**: `opensearch-cluster` for logical grouping.
- **Node Discovery**: Uses `discovery.seed_hosts` to allow nodes to find each other.
- **Data Persistence**: Data is stored in volumes mounted at `/usr/share/opensearch/data`.

### **Security**:
- SSL and security plugins are disabled (`plugins.security.disabled=true`) for simplicity.

### **Relationships**:
- OpenSearch acts as the backend for **Graylog** to index and store log data efficiently.

---

## **5. Graylog Configuration**
Graylog processes incoming logs, performs searches, and provides a web-based user interface.

### **Nodes**:
- **`graylog01`** (Master node), **`graylog02`**, and **`graylog03`**.
- Ports `1514`-`1516` (Syslog TCP) and `5044`-`5046` (Beats) are exposed for log ingestion.

### **Environment Variables**:
- **`GRAYLOG_IS_MASTER`**: True for `graylog01`, false for others.
- **MongoDB URI**: Points to all MongoDB nodes.
- **Elasticsearch Hosts**: Points to all OpenSearch nodes.
- **HTTP External URI**: Exposed as `https://graylog.sopaline.lan/`.

### **Traefik Integration**:
- Traefik routes incoming traffic to Graylog services using labels.
- **Custom Middleware**: Sets `X-Graylog-Server-URL` for the external web interface.

### **Relationships**:
- Graylog depends on **MongoDB** for configurations and **OpenSearch** for indexing and storing logs.
- Graylog nodes balance the processing of logs while the master node manages the cluster.

---

## **6. Traefik as Reverse Proxy**
Traefik acts as a **reverse proxy** and load balancer for the Graylog cluster, providing HTTPS termination.

### **Nodes**:
- Three Traefik replicas are deployed across Docker Swarm manager nodes.

### **Ports**:
- Port `80` for HTTP.
- Port `443` for HTTPS.

### **Certificates**:
- Mounted from `/home/admin/mnt-glusterfs/traefik/certs/` for HTTPS termination.

### **Dynamic Routing**:
- Traefik dynamically detects Graylog services using **labels**.
- All traffic to `https://graylog.sopaline.lan` is routed to Graylog nodes.

### **High Availability**:
- Using **Keepalived** with a VIP ensures Traefik is highly available.

---

## **7. Service Relationships Overview**
1. **Graylog**:
   - Reads/Writes data to **OpenSearch**.
   - Stores configurations and metadata in **MongoDB**.

2. **MongoDB**:
   - A 3-node replica set ensures redundancy and high availability.

3. **OpenSearch**:
   - Stores and indexes logs from Graylog.
   - Operates as a 3-node cluster for fault tolerance.

4. **Traefik**:
   - Balances HTTP/HTTPS traffic across Graylog nodes.
   - Manages SSL termination using certificates.

5. **GlusterFS**:
   - Provides persistent storage for all services.

---

## **8. Key Highlights**
- **Scalability**:
  - OpenSearch and Graylog nodes can be scaled horizontally to handle more load.
- **Fault Tolerance**:
  - High availability is ensured for MongoDB, OpenSearch, and Traefik.
- **HTTPS Security**:
  - Traefik manages HTTPS termination and routing for secure access.
- **Centralized Storage**:
  - GlusterFS provides a distributed filesystem for all service data.

---

## **Conclusion**
This Docker Swarm setup ensures a highly available, scalable, and secure Graylog cluster. Each service (MongoDB, OpenSearch, Graylog, and Traefik) is configured with redundancy, external networking, and persistent storage for stability in a production environment.
