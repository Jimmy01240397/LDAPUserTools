#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] GROUP

Options:
  -g, --gid GID                 change the group ID to GID
  -M, --members USERS           new list of supplementary USERS
  -a, --append                  append the USERS to this group
                                mentioned by the -M option without removing
                                other users
  -r, --remove                  remove the USERS to this group
                                mentioned by the -M option without appending
                                other users
  -h, --help                    display this help message and exit
  -n, --new-name NEW_GROUP      change the name to NEW_GROUP
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
newgroupname=""
gid=""
members=""
usersmode="replace"
url=""
binddn=""
bindpasswd=""

for a in $(seq 1 1 $argnum)
do
        nowarg=$1
        case "$nowarg" in
				-g|--gid)
                        shift
                        gid=$1
                        ;;
				-h|--help)
                        printhelp
                        ;;
                -M|--members)
                        shift
                        members=$(echo $1 | sed "s/,/ /g")
                        ;;
                -a|--append)
                        shift
                        usersmode="add"
                        ;;
                -r|--remove)
                        shift
                        usersmode="delete"
                        ;;
				-n|--new-name)
                        shift
                        newgroupname=$1
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

if [ "$url" != "" ]
then
	ldapurl="-H $url"
fi

gid=$(echo $gid | sed "s/[^0-9]//g")

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

oldgid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(cn=$groupname))" -LLL | grep -P "^gidNumber:" | awk '{print $2}' | sed "s/[^0-9]//g")

if [ "$gid" != "" ]
then
	for a in $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')
	do
		echo "dn: $a
changetype: modify
replace: gidNumber
gidNumber: $gid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	done
	echo "dn: cn=$groupname,ou=groups,$basedn
changetype: modify
replace: gidNumber
gidNumber: $gid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	oldgid=$gid
fi

if [ "$members" != "" ]
then
	members=$members" "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(gidNumber=$oldgid))" -LLL | grep -P "^cn:" | awk '{print $2}')
	modifybase="dn: cn=$groupname,ou=groups,$basedn
changetype: modify
${usersmode}: memberUid"
	for a in $members
	do
		modifybase=$modifybase"
memberUid: $a"
	done
	modifybase=$modifybase"
-
${usersmode}: member"
	for a in $members
	do
		modifybase=$modifybase"
member: cn=$a,ou=people,$basedn"
	done
	echo "$modifybase" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newgroupname" != "" ]
then
	echo "dn: cn=$groupname,ou=groups,$basedn
changetype: moddn
newrdn: cn=$newgroupname
deleteoldrdn: 1

dn: cn=$newgroupname,ou=groups,$basedn
changetype: modify
replace: cn
cn: $newgroupname" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi
