#!/bin/bash

if [ $# -lt 2 ]
then
    echo "Usage: $0 <your DC> <olcDatabase file>"
    exit 1
fi

slapadd -b cn=config -l membergroup.ldif
slapadd -b cn=config -l sshkey.ldif

slapadd -b cn=config -l overlaysetup.ldif

sed -i "s/by anonymous auth/by dn.exact=\"ou=Applications,$1\" auth/g" $2

sed '1,2d' $2 > /tmp/aaa
sed -i "s/# CRC32.*/# CRC32 $(crc32 /tmp/aaa)/g" $2
rm /tmp/aaa

systemctl restart slapd.service
