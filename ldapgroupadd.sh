#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] GROUP

Options:
  -g, --gid GID                 use GID for the new group
  -h, --help                    display this help message and exit
  -m, --members USERS			list of users of the new group
  -f, --bindfile				set url,binddn,bindpasswd with file
  -H, --url URL					LDAP Uniform Resource Identifier(s)
  -D, --binddn DN				bind DN
  -w, --bindpasswd PASSWORD		bind password"
	exit 0
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
	exit 0
fi

groupname=""
gid=""
users=""
url=""
binddn=""
bindpasswd=""

for a in $(seq 1 1 $argnum)
do
        nowarg=$1
        case "$nowarg" in
				-h|--help)
                        printhelp
                        ;;
                -g|--gid)
                        shift
                        gid=$1
                        ;;
                -m|--members)
                        shift
                        users=$(echo $1 | sed "s/,/ /g")
                        ;;
				-f|--bindfile)
						shift
						url=$(yq e '.url' $1)
						if [ "$url" == "null" ]
						then
							url=""
						fi
						binddn=$(yq e '.binddn' $1)
						if [ "$binddn" == "null" ]
						then
							binddn=""
						fi
						bindpasswd=$(yq e '.bindpasswd' $1)
						if [ "$bindpasswd" == "null" ]
						then
							bindpasswd=""
						fi
						;;
                -H|--url)
                        shift
                        url=$1
                        ;;
                -D|--binddn)
                        shift
                        binddn=$1
                        ;;
                -w|--bindpasswd)
                        shift
                        bindpasswd=$1
                        ;;
                *)
                        if [ "$nowarg" = "" ]
                        then
                                break
                        fi
						groupname=$1
                        ;;
        esac
        shift
done

if [ "$groupname" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your groupname and ldapbinddn."
	printhelp
fi

if [ "$bindpasswd" = "" ]
then
	read -p "Enter LDAP Password: " -s bindpasswd
fi

if [ "url" != "" ]
then
	ldapurl="-H $url"
fi

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

gid=$(echo $gid | sed "s/[^0-9]//g")

if [ "$gid" = "" ]
then
	gid=$(($(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(objectClass=posixGroup)" -LLL | grep gidNumber: | sort | tail -n 1 | awk '{print $2}' | sed "s/[^0-9]//g") + 1))
fi

if [ "$gid" = "1" ]
then
	gid=10000
fi

cat /etc/ldap/templates/group.ldif | sed "s/{dn}/cn=$groupname,ou=groups,$basedn/g" | sed "s/{groupname}/$groupname/g" | sed "s/{gid}/$gid/g" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"

for a in $users
do
	
	if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(uid=$a))" -LLL)" != "" ]
	then
		echo "dn: cn=$groupname,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $a
-
add: member
member: cn=$a,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
done


