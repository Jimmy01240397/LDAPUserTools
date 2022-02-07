#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -d, --home-dir HOME_DIR       home directory of the new account
  -g, --gid GROUP               name or ID of the primary group of the new
                                account
  -G, --groups GROUPS           list of supplementary groups of the new
                                account
  -h, --help                    display this help message and exit
  -N, --no-user-group           do not create a group with the same name as
                                the user
  -p, --password PASSWORD       password of the new account
  -s, --shell SHELL             login shell of the new account
  -u, --uid UID                 user ID of the new account
  -U, --user-group              create a group with the same name as the user
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
password=""
homedir=""
gid=""
uid=""
groups=""
genusergroup=true
shell=/bin/bash
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
                -d|--home-dir)
                        shift
                        homedir=$1
                        ;;
                -g|--gid)
                        shift
                        gid=$1
                        ;;
                -G|--groups)
                        shift
                        groups=$(echo $1 | sed "s/,/ /g")
                        ;;
                -N|--no-user-group)
                        genusergroup=false
                        ;;
                -U|--user-group)
                        genusergroup=true
                        ;;
                -s|--shell)
                        shift
                        shell=$1
                        ;;
                -u|--uid)
                        shift
                        uid=$1
                        ;;
                -p|--password)
                        shift
                        password=$1
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

if [ "$password" != "" ]
then
	userpassword="-s $password"
fi

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

if [ "$homedir" = "" ]
then
	homedir=/home/$username
fi

gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(|(gidNumber=$gid)(cn=$gid)))" -LLL | grep -P "^gidNumber:" | tail -n 1 | awk '{print $2}')


if [ "$gid" = "" ] && $genusergroup
then
	gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}')
	if [ "$gid" = "" ]
	then
		ldapgroupadd $ldapurl -D "$binddn" -w "$bindpasswd" $username
		gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}')
	fi
elif [ "$gid" = "" ] && ! $genusergroup
then
	gid=100
fi


uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$uid" = "" ]
then
	uid=$(($(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(objectClass=account)" -LLL | grep -P "^uidNumber:" | sort | tail -n 1 | awk '{print $2}' | sed "s/[^0-9]//g") + 1))
fi

if [ "$uid" = "1" ]
then
	uid=10000
fi

echo "dn: cn=$username,ou=people,$basedn
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: $username
uid: $username
userPassword: $(slappasswd $userpassword)
loginShell: $shell
uidNumber: $uid
gidNumber: $gid
homeDirectory: $homedir" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"

gidgroupname=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(gidNumber=$gid))" -LLL | grep -P "^cn:" | awk '{print $2}')

if [ "$gidgroupname" != "" ]
then
	echo "dn: cn=$gidgroupname,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi


for a in $groups
do
	if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(cn=$a))" -LLL)" != "" ]
	then
		echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
done
