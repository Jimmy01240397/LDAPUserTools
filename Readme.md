# LDAPUserTools
OpenLDAP User Tools.

## install
1. clone this repo and cd into LDAPUserTools.
``` bash
git clone https://github.com/Jimmy01240397/LDAPUserTools
cd LDAPUserTools
```

2. run install.sh
``` bash
sh install.sh
```

3. setup all schema
``` bash
bash initldapschema.sh
```

## usage
use -h to see info
``` bash
ldapuseradd -h
ldapgroupadd -h
ldapusermod -h
ldapgroupmod -h
ldapuserdel -h
ldapgroupdel -h
```

## example
Add group and user
``` bash
ldapgroupadd -D "cn=admin,dc=example,dc=com" -w "test1234" groupname
ldapuseradd -D "cn=admin,dc=example,dc=com" -w "test1234" -s /bin/bash username
```
or add a bindconf
``` bash
vi <pathofbindconf>/<nameofbindconf>.yaml
```
``` yaml
url: ldap://127.0.0.1
binddn: cn=admin,dc=example,dc=com
bindpasswd: test1234
```
``` bash
ldapgroupadd -f <pathofbindconf>/<nameofbindconf>.yaml groupname
ldapuseradd -f <pathofbindconf>/<nameofbindconf>.yaml -s /bin/bash username
```
