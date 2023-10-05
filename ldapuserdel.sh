#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -h, --help                    display this help message and exit
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

username=""
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
						username=$1
                        ;;
        esac
        shift
done

if [ "$username" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your username and ldapbinddn."
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

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

groupsdn=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" memberOf -LLL | grep -P "^memberOf:" | awk '{print $2}')

gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}')

gidgroupdn=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^dn:" | awk '{print $2}')

for a in $groupsdn
do
	echo "dn: $a
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
done

if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^memberUid:")" = "" ]
then
	ldapdelete -x $ldapurl -D "$binddn" -w "$bindpasswd" $gidgroupdn
else
	echo "$0: group $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^cn:" | awk '{print $2}') not removed because it has other members."
fi

ldapdelete -x $ldapurl -D "$binddn" -w "$bindpasswd" "cn=$username,ou=people,$basedn"
