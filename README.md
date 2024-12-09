# **Deployment Guide - High-Availability Docker Swarm Cluster with Graylog and Traefik**

Starting Graylog in your Lab with cluster mode (docker swarm)

This guide will help you run Graylog in cluster mode on multiple nodes thanks to Docker Swarm !
You need to pay attention to all the steps to take before running the docker stack YML file, because they will help you to achieve a real cluster environment with high availability.


## **1. Hardware and Software Requirements**

### Hardware
- **3 Swarm Manager VMs**: `gl-swarm-01`, `gl-swarm-02`, `gl-swarm-03`

### Software
- **OS**: Alma Linux 9.5
- **Docker**: Version 27.3.1
- **Traefik**: Reverse Proxy v3.2.1
- **Graylog**: Version 6.1.4
- **MongoDB**: Version 7.0.14
- **OpenSearch**: Version 2.15.0

---

## **2. VM and Network Configuration**

### 2.1 Configure Hosts

Edit and append DNS entries to the `/etc/hosts` file on **all VMs**:

```bash
cat <<EOF >> /etc/hosts
192.168.1.11   gl-swarm-01.sopaline.lan
192.168.1.12   gl-swarm-02.sopaline.lan
192.168.1.13   gl-swarm-03.sopaline.lan
192.168.1.100  graylog.sopaline.lan
EOF
```

### 2.2 Install Required Packages

Install the necessary tools on each **VM**:

```bash
# Update packages
sudo apt update && sudo apt upgrade -y

# Install Docker and Docker Compose
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

- **GlusterFS**: High-availability storage servers.
- **Keepalived**: For managing the **Virtual IP (VIP)**.
```
# Install GlusterFS and Keepalived
sudo dnf install epel-release centos-release-gluster10
sudo apt install glusterfs-server keepalived -y
sudo systemctl enable glusterd
sudo systemctl start glusterd
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

### 2.3 Set firewalld on all VMs

```
systemctl enable firewalld && systemctl start firewalld
sudo firewall-cmd --permanent --add-port=2377/tcp --zone=public
sudo firewall-cmd --zone=public --add-port=7946/tcp --permanent
sudo firewall-cmd --zone=public --add-port=7946/udp --permanent
sudo firewall-cmd --zone=public --add-port=4789/udp --permanent
sudo firewall-cmd --zone=public --add-service=glusterfs --permanent
sudo firewall-cmd --zone=public --add-port=9300/tcp --permanent
sudo firewall-cmd --zone=public --add-port=9200/tcp --permanent
firewall-cmd --reload
```
Or simply disable it: `systemctl disable firewalld && systemctl stop firewalld`

### 2.4 Set Up Docker Swarm Cluster

Initialize Docker Swarm on **gl-swarm-01**:
```bash
sudo docker swarm init --advertise-addr 192.168.1.10
docker swarm join-token manager
```
Copy the command described and paste it to **gl-swarm-02** and **gl-swarm-03**

Join **gl-swarm-02** and **gl-swarm-03** to the cluster:
```bash
sudo docker swarm join --token <SWARM_TOKEN> 192.168.1.10:2377
```
Verify the cluster:
```bash
sudo docker node ls
```

All nodes are part of Docker swarm cluster ! Then let's set GlusterFS for cluster storage that will be used by all of our containers across the swarm cluster.

## **3. GlusterFS Configuration**

### 3.1 Create Shared Volumes

On **gl-swarm-01**, **gl-swarm-02**, **gl-swarm-03**:

1. Create the storage:
   ```bash
   sudo mkdir /srv/glusterfs
   ```

2. Configure GlusterFS on **gl-swarm-01**:
   ```bash
   sudo gluster peer probe gl-swarm-02
   sudo gluster peer probe gl-swarm-03
   sudo gluster volume create gv0 replica 4 transport tcp gl-swarm-01:/srv/glusterfs gl-swarm-02:/srv/glusterfs gl-swarm-03:/srv/glusterfs
   sudo gluster volume start gv0
   ```
   Verify gluster cluster with: `sudo gluster peer status`

We will then use`/home/admin/mnt-glusterfs` as a mountpoint.

```
mkdir /home/admin/mnt-glusterfs
```

3. Mount the GlusterFS volume on **gl-swarm-01**:
   ```bash
   echo 'gl-swarm-01:/gv0    /home/admin/mnt-glusterfs    glusterfs    defaults,_netdev  0 0' | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload && mount -a
   { crontab -l; echo "@reboot mount -a"; } | sudo crontab -
   ```
4. Mount the GlusterFS volume on **gl-swarm-02**:
   ```bash
   echo 'gl-swarm-02:/gv0    /home/admin/mnt-glusterfs    glusterfs    defaults,_netdev  0 0' | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload && mount -a
   { crontab -l; echo "@reboot mount -a"; } | sudo crontab -
   ```
5. Mount the GlusterFS volume on **gl-swarm-03**:
   ```bash
   echo 'gl-swarm-03:/gv0    /home/admin/mnt-glusterfs    glusterfs    defaults,_netdev  0 0' | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload && mount -a
   { crontab -l; echo "@reboot mount -a"; } | sudo crontab -
   ```

 6.  Change the permissions according to your user, (mine is admin):
 ```
 sudo chown -R admin:admin /home/admin/mnt-glusterfs/
 ```

## **4. Keepalived Configuration (VIP)**

Create a `/etc/keepalived/keepalived.conf` file on each manager VM. 
Check your active network card before pasting the cat EOF command: `ip a`

For **gl-swarm-01**:
```bash
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface ens18  
    virtual_router_id 51
    priority 100      # Master node higher priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24  # VIP
    }
}
EOF
```

Restart Keepalived:
```bash
sudo systemctl restart keepalived
```

For **gl-swarm-02**:
```bash
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state BACKUP
    interface ens18   # Network card (vérifiez with "ip a")
    virtual_router_id 51
    priority 90      # Master node higher priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24  # VIP
    }
}
EOF
```

Restart Keepalived:
```bash
sudo systemctl restart keepalived
```

For **gl-swarm-01**:
```bash
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state BACKUP
    interface ens18   # Network card (vérifiez with "ip a")
    virtual_router_id 51
    priority 80      # Master node higher priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24  # VIP
    }
}
EOF
```

Restart Keepalived:
```bash
sudo systemctl restart keepalived
```

## **5. Deploy the Stack**

### 5.1 Prepare network

Create an overlay network: `docker network create -d overlay --attachable gl-swarm-net`, it will be used in the docker compose files as an external network. 
This network will allow to all containers across the nodes to communicate between them.

### 5.2 Prepare the containers folders

```
mkdir -p /home/admin/mnt-glusterfs/{graylog/{csv,gl01-data,gl02-data,gl03-data},opensearch/{os01-data,os02-data,os03-data},mongodb{mongo01-data,mongo02-data,mongo03-data,initdb.d},traefik/certs}
```

The folder tree will look like this
```
/home/admin/mnt-glusterfs/
├── graylog
│   ├── csv
│   ├── gl01-data
│   ├── gl02-data
│   └── gl03-data
├── opensearch
│   ├── os01-data
│   ├── os02-data
│   └── os03-data
├── mongodb
│   ├── mongo01-data
│   ├── mongo02-data
│   ├── mongo03-data
│   └── initdb.d
└── traefik
    └── certs
```

### 5.2 Prepare the containers files




# DEFAULTS CREDS

- Graylog WEB UI
   - user: admin
   - pasword: admin



# PROXMOX

1. Create 3 VMs
   
![image](https://github.com/user-attachments/assets/3c6a174f-822d-40ee-a988-e2b0e24b960f)

3. Choose Host for the CPU on Hardware settings:

![image](https://github.com/user-attachments/assets/2f776733-4eaa-4098-8f36-18137919d141)

If not, you will have a message error for MongoDB: `WARNING: MongoDB 5.0+ requires a CPU with AVX support, and your current system does not appear to have that!`


# DNS

![image](https://github.com/user-attachments/assets/f983f54d-92d2-4511-99b8-d5914a80ed6c)

# Docker

1. Install docker
2.  Configure non sudoers users to use docker: `sudo usermod -aG docker $USER`






Now that our Docker Swarm cluster is initialized and all nodes are active, we can move on to the next step: managing storage, particularly before deploying Graylog in containers.

The Docker configuration for deploying Graylog is defined in a single YAML file. However, when the containers are deployed, the volumes specified in the file point to local paths on the node where the container is running. If these paths are not shared across all nodes in the cluster, it will result in issues with data access or consistency.

To avoid these problems and ensure distributed and consistent storage accessible from all nodes, it is essential to use GlusterFS.

GlusterFS allows the volumes to be shared seamlessly across all nodes in the Swarm cluster, ensuring data availability regardless of where the containers are deployed.

## GlusterFS

```
sudo dnf install epel-release centos-release-gluster10 
apt install -y glusterfs-server
dnf install glusterfs-server
systemctl enable glusterd
systemctl start glusterd
systemctl enable --now glusterd
sudo firewall-cmd --add-service=glusterfs --permanent
Sudo firewall-cmd --reload
```

```
gluster peer probe gl-swarm-02
gluster peer probe gl-swarm-03
gluster peer probe gl-swarm-04
```

- Check the GlusterFS Status
```
gluster peer status
```
![image](https://github.com/user-attachments/assets/5cc4bd39-3b96-4fec-abe8-ef853ba06ee3)


On each node, create a folder: `mkdir /srv/glusterfs` then from one of the glusterfs member cluster, run this command to create the Gluster volumes:

```
sudo gluster volume create gv0 replica 4 transport tcp gl-swarm-01:/srv/glusterfs gl-swarm-02:/srv/glusterfs gl-swarm-03:/srv/glusterfs gl-swarm-04:/srv/glusterfs
Sudo gluster volume start gv0
```

- Verify the cluster Glusterfs: `sudo gluster volume info`
![image](https://github.com/user-attachments/assets/2604df41-52aa-4974-8de3-1ca59be8ae52)

- gl-swarm-01
```
sudo mkdir -p /home/admin/mnt-glusterfs
echo "gl-swarm-01:/gv0 /home/admin/mnt-glusterfs glusterfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
```

- gl-swarm-02
```
sudo mkdir -p /home/admin/mnt-glusterfs
echo "gl-swarm-02:/gv0 /home/admin/mnt-glusterfs glusterfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
```

- gl-swarm-03
```
sudo mkdir -p /home/admin/mnt-glusterfs
echo "gl-swarm-03:/gv0 /home/admin/mnt-glusterfs glusterfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
```

If your user is admin, run: `sudo chown -R admin:admin mnt-glusterfs/`

Add for all the nodes in crontab the mounting of glusterfs:

```
crontab -e
@reboot mount -a
```

# Opensearch

```
sudo firewall-cmd --zone=public --add-port=9300/tcp --permanent
sudo firewall-cmd --zone=public --add-port=9200/tcp --permanent
sudo firewall-cmd --reload
```

### CLUSTER GRAYLOG

Run the docker stack, the docker-stack.yml contain Opensearch, mongodb and Graylog configuration using GlusteFS volumes.

```
docker stack deploy -c docker-stack.yml Graylog-Swarm
```

To view if the 3 containers on each node is running, run: `docker ps`

![image](https://github.com/user-attachments/assets/7ad426a8-bc23-49e0-82a6-e7d82ca84e6c)

To view if the service stack is opearationnel and everything has a replicas, run: `docker stack services Graylog-Swarm`

![image](https://github.com/user-attachments/assets/57082965-3b6b-4b76-a844-c3d0182dadfc)

You can check by accessing the URL of graylog node1:
![image](https://github.com/user-attachments/assets/534f8441-1caa-4007-aa88-2c92e59ab0ea)

If you see the message error about multiple master, you can ignore, it appears only at first startup, to check run this: `curl -u admin:admin http://127.0.0.1:9000/api/system/cluster/nodes | jq .`

![image](https://github.com/user-attachments/assets/d81a5e72-9865-47c3-8dca-2bc3946e6cbb)

All good ! :)

You are now accessing Graylog directly, it's best to use a reverse proxy to handle HTTPS and certificates and load balancing:

Create a folder for your glusterfs: `mkdir -p /home/admin/mnt-glusterfs/traefik/certs`



Use the docker-stack-with-Traefik.yml


Check again the cluster node via API, but this time use the HTTPS: `curl -u admin:admin -k https://graylog.sopaline.lan:443/api/system/cluster/nodes | jq .`

![image](https://github.com/user-attachments/assets/0ae35461-de52-4e81-83e6-efd3a79631a4)

## HIGH AVAILABILITY 

One problem remains, even if traefik is in swarm mode, as the DNS entry point to the IP Addresse of the first VM, if this VM is down, access to graylog will not be working.
We need to create a VIP with Keepalive.

On all VM nodes (not docker), install Keepalive:
```
sudo dnf install -y keepalived
```

Edit the conf Keepalive: /etc/keepalived/keepalived.conf

- Keepalive node 1: 
```
! Configuration File for keepalived

vrrp_instance VI_1 {
    state MASTER
    interface ens18   # Network card (vérifiez with "ip a")
    virtual_router_id 51
    priority 100      # Master node higher priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24  # VIP
    }
}
```

- Keepalive node 2:

```
vrrp_instance VI_1 {
    state BACKUP
    interface ens18
    virtual_router_id 51
    priority 90       # Lower priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24
    }
}
```

- Keepalive node 3: 

```
vrrp_instance VI_1 {
    state BACKUP
    interface ens18
    virtual_router_id 51
    priority 80       # Lower priority
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass somepassword
    }
    virtual_ipaddress {
        192.168.30.100/24
    }
}
```
Enable and restart the services:
```
sudo systemctl enable keepalived
sudo systemctl restart keepalived
```

Check the IP VIP
```
ip a | grep 192.168.30.100
    inet 192.168.30.100/24 scope global secondary ens18
```

And change the DNS to point to the VIP, done ! 

# Credits 

Thanks to for the understanding of the basics:

- https://workingtitle.pro/posts/graylog-on-docker-part-1/
- https://workingtitle.pro/posts/graylog-on-docker-part-2/
- https://workingtitle.pro/posts/graylog-on-docker-part-3/
- https://community.graylog.org/t/quick-guide-graylog-deployment-with-ansible-and-docker-swarm/12365
