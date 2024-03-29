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
  -k, --sshkeys KEYS            Your sshkeys for this account
  -e, --email EMAIL             Set user email
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
sshkeysmode="replace"
sshkeys=""
groups=""
shell=""
email=""
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
                        groups=$1  #$(echo $1 | sed "s/,/ /g")
                        ;;
                -a|--append)
                        if [ $2 == "-G" ] || [ $2 == "--groups" ]
                        then
                            groupsmode="add"
                        elif [ $2 == "-k" ] || [ $2 == "--sshkeys" ]
                        then
                            sshkeysmode="add"
                        fi
                        ;;
                -r|--remove)
                        if [ $2 == "-G" ] || [ $2 == "--groups" ]
                        then
                            groupsmode="delete"
                        elif [ $2 == "-k" ] || [ $2 == "--sshkeys" ]
                        then
                            sshkeysmode="delete"
                        fi
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
                -P|--Password)
                        promptpassword=true
                        ;;
                -k|--sshkeys)
                        shift
                        sshkeys=$(echo $1 | sed "s/,/ /g")
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
then
	newpasswd=$(slappasswd -s $password)
fi

if $promptpassword && [ "$userpassword" = "" ]
then
	exit 0
fi


basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

oldgid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}' | sed "s/[^0-9]//g")

if [ "$gid" != "100" ]
then
	gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(|(gidNumber=$gid)(cn=$gid)))" -LLL | grep -P "^gidNumber:" | tail -n 1 | awk '{print $2}')
fi

uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$homedir" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: homeDirectory
homeDirectory: $homedir" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$shell" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: loginShell
loginShell: $shell" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newpasswd" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: userPassword
userPassword: $newpasswd" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$uid" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: uidNumber
uidNumber: $uid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$email" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: mail
mail: $email" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$gid" != "" ]
then
	if [ "$oldgid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
	
	if [ "$gid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi

	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: gidNumber
gidNumber: $gid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	
	oldgid=$gid
fi

if [ "$groups" != "" ]
then
	case "$groupsmode" in
			replace)
					for a in $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" memberOf -LLL | grep -P "^memberOf:" | awk '{print $2}')
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')" ]
						then
							echo "dn: $a
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done

                    IFS=,
					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			add)
                    IFS=,
					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			delete)
                    IFS=,
					for a in $groups
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^cn:" | awk '{print $2}')" ]
						then
							echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done
					;;
	esac
    IFS=" "
fi

if [ "$sshkeys" != "" ]
then
	modifybase="dn: cn=$username,ou=people,$basedn
changetype: modify
${sshkeysmode}: sshkey"
	for a in $sshkeys
	do
		modifybase=$modifybase"
sshkey: cn=$a,ou=sshkey,$basedn"
	done
	echo "$modifybase" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newusername" != "" ]
then
	allgroups="$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" memberOf -LLL | grep -P "^memberOf:" | awk '{print $2}')"
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
changetype: modify
delete: memberUid
memberUid: $username
-
add: memberUid
memberUid: $newusername" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	done
fi

