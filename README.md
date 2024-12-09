# Graylog-Cluster-Docker-Swarm
Starting Graylog in your Lab with cluster mode (docker swarm)

This guide will help you run Graylog in cluster mode on multiple nodes thanks to Docker Swarm !

# STILL IN WRITING PROCESS, NEED TO IMPROVE DOCUMENTATION

# Prerequisites:

- Understanding of Linux / Systems
- Understanding of Docker
- 3 VMs (Alma Linux for this Guide)
- Standard Linux user (non sudoers)
- DNS server or use /etc/hosts

# DEFAULTS

- Graylog WEB UI
user: admin
pasword: admin

# Details of the Lab

192.168.30.0/24

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
3.  Create a swarm network: `docker network create -d overlay --attachable gl-swarm-net`, it will be used in the docker compose files as an external network, (created manually)

## Swarm

A manager node can be a worker node.

1. Initialize the first node
```
docker swarm init --advertise-addr 192.168.30.10
```

3. To add other manager, run this command on the initalized one to generate a token registration:

```
docker swarm join-token manager 
```

4. Adding the other managers, run the command on the other node
```
docker swarm join --token SWMTKN-1-3txjoa48gdvvzzsjce09ovbmdc4xrq35j7jalxa53er6i6tnnj-1zdfv147ny5xoohiau7l0mxy2 192.168.30.10:2377
```

5. View the swarm cluster
```
docker node ls
```

![image](https://github.com/user-attachments/assets/77f736a2-b830-4eda-97e7-61572b741a94)


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
    interface ens18   # Network card (check with "ip a")
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
