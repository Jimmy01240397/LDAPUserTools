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
  -k, --sshkeys KEYS            Your sshkeys for this account
  -s, --shell SHELL             login shell of the new account
  -u, --uid UID                 user ID of the new account
  -U, --user-group              create a group with the same name as the user
  -e, --email EMAIL             Set user email
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
sshkeys=""
homedir=""
gid=""
uid=""
email=""
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
                        groups=$1         #$(echo $1 | sed "s/,/ /g")
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
                -e|--email)
                        shift
                        email=$1
                        ;;
                -p|--password)
                        shift
                        password=$1
                        ;;
                -k|--sshkeys)
                        shift
                        sshkeys=$(echo $1 | sed "s/,/ /g")
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
	userpassword="$(slappasswd -s $password)"
else
	userpassword="$(slappasswd)"
fi

if [ "$userpassword" = "" ]
then
	exit 0
fi

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

if [ "$homedir" = "" ]
then
	homedir=/home/$username
fi

gidexist=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(|(gidNumber=$gid)(cn=$gid)))" -LLL | grep -P "^gidNumber:" | tail -n 1 | awk '{print $2}')


if [ "$gidexist" = "" ] && $genusergroup
then
    if [ "$gid" = "" ]
    then
    	gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}')
        gidexist=$gid
    fi
    if [ "$gidexist" = "" ]
	then
        if [ "$gid" = "" ]
        then
		    ldapgroupadd $ldapurl -D "$binddn" -w "$bindpasswd" $username
        else
		    ldapgroupadd $ldapurl -D "$binddn" -w "$bindpasswd" -g "$gid" $username
        fi
		gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}')
	fi
elif [ "$gid" = "" ] && ! $genusergroup
then
	gid=100
fi


uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$uid" = "" ]
then
	uid=$(($(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(objectClass=person)" -LLL | grep -P "^uidNumber:" | awk '{print $2}' | sort -n | tail -n 1 | sed "s/[^0-9]//g") + 1))
fi

if [ "$uid" = "1" ]
then
	uid=10000
fi

echo "dn: cn=$username,ou=people,$basedn
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: sshAccount
cn: $username
sn: $username
uid: $username
userPassword: $userpassword
loginShell: $shell
uidNumber: $uid
gidNumber: $gid
homeDirectory: $homedir" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"

if [ "$email" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: mail
mail: $email" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

gidgroupname=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^cn:" | awk '{print $2}')

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

IFS=,
for a in $groups
do
	if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(cn=$a))" -LLL)" != "" ]
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
IFS=" "

for a in $sshkeys
do
	if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=sshPublicKey)(cn=$a))" -LLL)" != "" ]
	then
	    echo "dn: cn=$username,ou=people,$basedn
changetype: modify
add: sshkey
sshkey: cn=$a,ou=sshkey,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
done

