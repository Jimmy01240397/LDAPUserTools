#!/bin/bash


sed -i "s/MAY ( userPassword \$ memberUid \$ description ) )/MAY ( userPassword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/schema/nis.schema

sed -i "s/sword \$ memberUid \$ description ) )/sword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/schema/nis.ldif

sed -i "s/rPassword \$ memberUid \$ description ) )/rPassword \$ memberUid \$ member \$ description ) )/g" /etc/ldap/slapd.d/cn\=config/cn\=schema/cn\=\{2\}nis.ldif


