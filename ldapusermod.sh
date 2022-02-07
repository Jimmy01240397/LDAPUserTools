#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -g, --gid GROUP               force use GROUP as new primary group
  -G, --groups GROUPS           new list of supplementary GROUPS
  -a, --append                  append the user to the supplemental GROUPS
                                mentioned by the -G option without removing
                                the user from other groups
  -r, --remove                  remove the user to the supplemental GROUPS
                                mentioned by the -G option without appending
                                the user from other groups
  -h, --help                    display this help message and exit
  -l, --login NEW_LOGIN         new value of the login name
  -p, --password PASSWORD       password of the new password
  -P, --Password				prompt for new password 
  -s, --shell SHELL             new login shell for the user account
  -u, --uid UID                 new UID for the user account
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
newusername=""
password=""
promptpassword=false
homedir=""
gid=""
uid=""
groupsmode="replace"
groups=""
shell=""
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
                -a|--append)
                        shift
                        groupsmode="add"
                        ;;
                -r|--remove)
                        shift
                        groupsmode="delete"
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
                -P|--Password)
                        shift
                        promptpassword=true
                        ;;
                -l|--login)
                        shift
                        newusername=$1
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

newpasswd=""
if $promptpassword
then
	newpasswd=$(slappasswd)
elif [ "$password" != "" ]
	newpasswd=$(slappasswd -s $password)
fi

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

oldgid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}' | sed "s/[^0-9]//g")

if [ "$gid" != "100" ]
then
	gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(|(gidNumber=$gid)(cn=$gid)))" -LLL | grep -P "^gidNumber:" | tail -n 1 | awk '{print $2}')
fi

uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$homedir" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modifly
replace: homeDirectory
homeDirectory: $homedir" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$shell" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modifly
replace: loginShell
loginShell: $shell" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newpasswd" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modifly
replace: userPassword
userPassword: $newpasswd" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$uid" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modifly
replace: uidNumber
uidNumber: $uid" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$gid" != "" ]
then
	if [ "$oldgid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modifly
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
	
	if [ "$gid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(gidNumber=$gid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modifly
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi

	echo "dn: cn=$username,ou=people,$basedn
changetype: modifly
replace: gidNumber
gidNumber: $gid" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
	
	oldgid=$gid
fi

if [ "$groups" != "" ]
then
	case "$groupsmode" in
			replace)
					for a in $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(uid=$username))" -LLL | grep -P "^memberOf:" | awk '{print $2}')
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')" ]
						then
							echo "dn: $a
changetype: modifly
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done

					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modifly
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			add)
					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modifly
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			delete)
					for a in $groups
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=groupOfNames)(gidNumber=$oldgid))" -LLL | grep -P "^cn:" | awk '{print $2}')" ]
						then
							echo "dn: cn=$a,ou=groups,$basedn
changetype: modifly
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done
					;;
	esac
fi


if [ "$newusername" != "" ]
then
	allgroups="$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=account)(uid=$username))" -LLL | grep -P "^memberOf:" | awk '{print $2}')"
	echo "dn: cn=$username,ou=people,$basedn
changetype: moddn
newrdn: cn=$newusername
deleteoldrdn: 1

dn: cn=$newusername,ou=people,$basedn
changetype: modify
replace: cn
cn: $newusername
-
replace: uid
uid: $newusername" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"

	for a in $allgroups
	do
		echo "dn: $a
changetype: modifly
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn
-
add: memberUid
memberUid: $newusername
-
add: member
member: cn=$newusername,ou=people,$basedn" | ldapmodifly -x $ldapurl -D "$binddn" -w "$bindpasswd"
	done
fi
