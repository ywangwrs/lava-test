FROM lavasoftware/lava-server:2020.05

ENV container docker

RUN find /etc/systemd/system \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
 lava-tool \
 tzdata \
 && apt-get clean

# Override settings.conf with LDAP integration
ADD configs/settings.conf /etc/lava-server/settings.conf

COPY scripts/setup.sh .
COPY jobs/samples/* /root/jobs/

# Add device-types and devices
ADD devices/* /etc/lava-server/dispatcher-config/devices/
ADD device-types/* /etc/lava-server/dispatcher-config/device-types/

RUN cd /etc/lava-server/dispatcher-config \
 && chown lavaserver:lavaserver devices/* device-types/*

# Temporarily fix the issue of context limitation which introduced from LAVA 2020.01
COPY scripts/__init__.py /usr/lib/python3/dist-packages/lava_common/schemas/

# setup.sh run as a service
#COPY configs/lava-test.service /lib/systemd/system/
#WORKDIR /etc/systemd/system/multi-user.target.wants
#RUN ln -s /lib/systemd/system/lava-test.service ./lava-test.service

WORKDIR /root/jobs

EXPOSE 69/udp 80 3079 5555 5556

