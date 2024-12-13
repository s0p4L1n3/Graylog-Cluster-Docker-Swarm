# **Deployment Guide - High-Availability Docker Swarm Cluster with Graylog and Traefik**

Starting Graylog in your Lab with cluster mode (docker swarm)

This guide will help you run Graylog in cluster mode on multiple nodes thanks to Docker Swarm !
You need to pay attention to all the steps to take before running the docker stack YML file, because they will help you to achieve a real cluster environment with high availability.

![image](https://github.com/user-attachments/assets/9daa469a-81bb-4dd4-9616-444b21b1c64a)

## **1. Hardware and Software Requirements**

### Hardware
- **3 Swarm Manager VMs**: `gl-swarm-01`, `gl-swarm-02`, `gl-swarm-03`

#### Example hardware PROXMOX

1. Create 3 VMs
   
![image](https://github.com/user-attachments/assets/3c6a174f-822d-40ee-a988-e2b0e24b960f)

2. Choose Host for the CPU on Hardware settings:

![image](https://github.com/user-attachments/assets/2f776733-4eaa-4098-8f36-18137919d141)

If not, you will have a message error for MongoDB: `WARNING: MongoDB 5.0+ requires a CPU with AVX support, and your current system does not appear to have that!`

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
192.168.30.10   gl-swarm-01.sopaline.lan
192.168.30.11   gl-swarm-02.sopaline.lan
192.168.30.12   gl-swarm-03.sopaline.lan
192.168.30.100  graylog.sopaline.lan
EOF
```

### 2.2 Install Required Packages

Install the necessary tools on each **VM**:

```bash
# Update packages
sudo dnf update -y && sudo dnf upgrade -y

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
sudo dnf install epel-release centos-release-gluster10 -y
sudo dnf install glusterfs-server keepalived -y
sudo systemctl enable glusterd
sudo systemctl start glusterd
sudo systemctl enable keepalived
```

Do not start now the Keepalive service.

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
sudo docker swarm init --advertise-addr 192.168.30.10
docker swarm join-token manager
```
Copy the command described and paste it to **gl-swarm-02** and **gl-swarm-03**

Join **gl-swarm-02** and **gl-swarm-03** to the cluster:
```bash
sudo docker swarm join --token <SWARM_TOKEN> 192.168.30.10:2377
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

Start/Restart Keepalived:
```bash
sudo systemctl start keepalived
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
sudo systemctl start keepalived
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
sudo systemctl start keepalived
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

- Init script for set replicas mongodb
```
wget -O /home/admin/mnt-glusterfs/mongodb/init-replset.js https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/main/mnt-glusterfs/mongodb/init-replset.js
wget -O /home/admin/mnt-glusterfs/mongodb/initdb.d/init-replset.sh https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/main/mnt-glusterfs/mongodb/initdb.d/init-replset.sh
```

- Traefik files and demo cert:
```
wget -O /home/admin/mnt-glusterfs/traefik/traefik.yaml https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/refs/heads/main/mnt-glusterfs/traefik/traefik.yaml
wget -O /home/admin/mnt-glusterfs/traefik/certs/graylog.sopaline.lan.crt https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/refs/heads/main/mnt-glusterfs/traefik/certs/graylog.sopaline.lan.crt
wget -O /home/admin/mnt-glusterfs/traefik/certs/graylog.sopaline.lan.key https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/refs/heads/main/mnt-glusterfs/traefik/certs/graylog.sopaline.lan.key
```

- Docker stack compose file
```
wget /home/admin/docker-stack.yml -O https://raw.githubusercontent.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/refs/heads/main/docker-stack-with-Traefik.yml
```

BE CAREFUL HERE ! Before running the stack read this below:

- The Docker configuration for deploying Graylog is defined in a single YAML file. However, when the containers are deployed, the volumes specified in the file point to local paths on the node where the container is running. If these paths are not shared across all nodes in the cluster, it will result in issues with data access or consistency.

- Without Keepalive, one problem remains, even if traefik is in swarm mode, as the DNS entry point to the IP Addresse of the first VM, if this VM is down, access to graylog will not be working. We need that the DNS point to the VIP so that any Traefik can respond.


### 5.3 Run the cluster !

```
docker stack deploy -c docker-stack.yml Graylog-Swarm
```
#### 5.3.1 Verify stack services 

To view if the service stack is opearationnel and everything has a replicas, run: `docker stack services Graylog-Swarm`

![image](https://github.com/user-attachments/assets/6300d299-d372-4035-b179-1a69336b4be0)

#### 5.3.2 View stack service enhanced

```
sh /home/admin/mnt-glusterfs/view-services.sh
```
![image](https://github.com/user-attachments/assets/9faf5c62-f746-48f9-819e-d5a6a14c1bd7)



#### 5.3.1 Verify Graylog API

Check cluster node via API, use the HTTPS: `curl -u admin:admin -k https://graylog.sopaline.lan:443/api/system/cluster/nodes | jq .`

![image](https://github.com/user-attachments/assets/0ae35461-de52-4e81-83e6-efd3a79631a4)

#### 5.3.2 Verify Graylog access to web UI !

![image](https://github.com/user-attachments/assets/0321f66a-1275-48be-8eaa-4ee2375e8f8f)


## 6 DEFAULTS CREDS

- Graylog WEB UI
   - user: admin
   - pasword: admin

# 7 :blue_book: Docker-stack.YML config

[Docker Stack File Config](https://github.com/s0p4L1n3/Graylog-Cluster-Docker-Swarm/blob/main/DockerStack-configfile.md)


# 8 Credits 

Thanks to for the understanding of the basics:

- https://workingtitle.pro/posts/graylog-on-docker-part-1/
- https://workingtitle.pro/posts/graylog-on-docker-part-2/
- https://workingtitle.pro/posts/graylog-on-docker-part-3/
- https://community.graylog.org/t/quick-guide-graylog-deployment-with-ansible-and-docker-swarm/12365
