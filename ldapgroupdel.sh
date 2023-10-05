#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] GROUP

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

groupname=""
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

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(cn=$groupname))" -LLL | grep -P "^gidNumber:" | awk '{print $2}' | sed "s/[^0-9]//g")

if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(gidNumber=$gid))" -LLL)" != "" ]
then
	echo "$0: cannot remove the primary group of user '$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(gidNumber=$gid))" -LLL | grep -P "^uid:" | sed -n '1p' | awk '{print $2}')'."
	exit 0
fi

ldapdelete -x $ldapurl -D "$binddn" -w "$bindpasswd" "cn=$groupname,ou=groups,$basedn"