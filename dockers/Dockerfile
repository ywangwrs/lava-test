FROM windriver/lava-base:latest

ENV container docker

RUN find /etc/systemd/system \             
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
 sshpass \
 nfs-kernel-server \
 git \
 vim \
 tzdata \
 && apt-get clean

# Override settings.conf with LDAP integration
ADD configs/settings.conf /etc/lava-server/settings.conf

COPY scripts/setup.sh .
COPY scripts/telnet_delay.sh /root
COPY jobs/* /root/jobs/

# Add device-types and devices
ADD devices/* /etc/lava-server/dispatcher-config/devices/
ADD device-types/* /etc/lava-server/dispatcher-config/device-types/

# setup.sh run as a service
COPY configs/lava-test.service /lib/systemd/system/
WORKDIR /etc/systemd/system/multi-user.target.wants
RUN ln -s /lib/systemd/system/lava-test.service ./lava-test.service

# QEMU setup
#ADD libguestfs/boot /boot
#ADD libguestfs/modules /lib/modules
#RUN /usr/bin/libguestfs-test-tool

WORKDIR /root/jobs

EXPOSE 69/udp 80 3079 5555 5556

STOPSIGNAL SIGRTMIN+3                                                           
                                                                                
# Workaround for docker/docker#27202, technique based on comments from docker/docker#9212
CMD ["/bin/bash", "-c", "exec /sbin/init --log-target=journal 3>&1"]  

