#!/bin/bash

slapadd -b cn=config -l membergroup.ldif
slapadd -b cn=config -l sshkey.ldif

slapadd -b cn=config -l overlaysetup.ldif


systemctl restart slapd.service
