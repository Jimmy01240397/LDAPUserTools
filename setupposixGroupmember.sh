#!/bin/bash

sed -i "s/MAY ( userPassword \$ memberUid \$ description ) )/MAY ( userPassword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/schema/nis.schema

sed -i "s/sword \$ memberUid \$ description ) )/sword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/schema/nis.ldif

sed -i "s/rPassword \$ memberUid \$ description ) )/rPassword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/slapd.d/cn\=config/cn\=schema/cn\=\{2\}nis.ldif

sed '1,2d' /etc/ldap/slapd.d/cn\=config/cn\=schema/cn\=\{2\}nis.ldif > /tmp/aaa

sed -i "s/# CRC32.*/# CRC32 $(crc32 /tmp/aaa)/g" /etc/ldap/slapd.d/cn\=config/cn\=schema/cn\=\{2\}nis.ldif

echo "dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib/ldap
olcModuleLoad: memberof

dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: posixGroup
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf" | ldapadd -Q -Y EXTERNAL -H ldapi:///

systemctl restart slapd.service
