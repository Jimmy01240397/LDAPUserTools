#!/bin/bash

passwd=""

if [ -f /etc/libnss-ldap.secret ]
then
    passwd="$(cat /etc/libnss-ldap.secret)"
elif [ -f /etc/ldap.secret ]
then
    passwd="$(cat /etc/ldap.secret)"
fi

url="$(grep "^uri" /etc/nslcd.conf | awk '{print $2}')"

base="$(grep "^base" /etc/nslcd.conf | awk '{print $2}')"

binddn=""

if [ -f /etc/libnss-ldap.conf ]
then
    binddn="$(grep "^rootbinddn" /etc/libnss-ldap.conf | awk '{print $2}')"
elif [ -f /etc/ldap.conf ]
then
    binddn="$(grep "^rootbinddn" /etc/ldap.conf | awk '{print $2}')"
fi


sshkeydn="$(ldapsearch -x -H $url -b "$base" -D "$binddn" -w $passwd '(&(objectClass=posixAccount)(uid='"$1"'))' 'sshkey' | sed -n '/^ /{H;d};/sshkey:/x;$g;s/\n *//g;s/sshkey: //gp')"


for a in $sshkey
do
    ldapsearch -x -H $url -b "$a" -D "$binddn" -w $passwd '(objectClass=sshPublicKey)' 'sshpubkey' | sed -n '/^ /{H;d};/sshpubkey:/x;$g;s/\n *//g;s/sshpubkey: //gp'
done
