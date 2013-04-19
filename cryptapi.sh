#!/bin/bash

set -e

function bootstrap {
    fuser=$1
    upass=$2
# initializes passman into a usable state, using '$1' as its initial administrator
# '$2' is the initial user's password
# returns an error if any remnants of a working state are detected, in which case it does nothing

    count=0
    for i in user group pass
    do
	[ -e $i ] && (( count++ ))
    done
    
    if [ "$count" = 0 ]
    then
	mkdir user
	mkdir group
	mkdir pass
	utoken=$(make-token)
	atoken=$(make-token)

	encrypt user/$fuser $upass $utoken
	encrypt group/admin.$fuser $utoken $atoken
	encrypt user/$fuser.admin $atoken $utoken

    elif [ "$count" = 3 ] && [ -e group/admin.* ]
    then
	echo "passman seems to be bootstrapped already, not doing anything."
	return 1

    else
	echo "passman seems to be in an inconsistent state, please clean up before trying to bootstrap."
	return 2
    fi
}

function validate-user {
    uname=$1
    pass=$2
# prints the token associated with '$1' by decrypting the file 
# user/'$1' with '$2'
# if the decryption encounters an error, its error code is returned
    
    decrypt user/$uname $pass
}

function validate-admin {
    uname=$1
    pass=$2
# prints the token associated with '$1' by decrypting the file
# group/admin.'$1' with '$2'
# if the decryption encounters an error, its error code is returned

    decrypt group/admin.$uname $pass
}

function encrypt {
    name="$1"
    pass="$2"
    cont="$3"
# encrypts '$3' in '$1' with '$2'
# if the file exists, an error is returned
# if the encryption encounters an error, its error code is returned

    [ -e $name ] && return 10

    touch $name
    chmod 600 $name
    echo "$cont" > $name

    export pass
    ccrypt -eq -S "" -E pass $name 2>/dev/null
}

function decrypt {
    name="$1"
    pass="$2"
# tries to decrypt and print '$1' using '$2'
# if the decryption encounters an error, its error code is returned
    
    export pass
    ccrypt -cq -E pass $name 2>/dev/null
}

function make-token {
# prints a generated string for use as intermediate encryption key for groups/users

    pwgen -s 128 1
}

function list-user-groups {
    uname=$1
# prints all groups that '$1' belongs to as a space-delimited list
    
    echo $(ls group/*.$uname 2>/dev/null | sed -r -e "s%^group/%%" -e "s%\.$uname$%%" | tr ' ' '\n' | sort -u)
}

function list-group-passes {
    gname=$1
# prints all password files belonging to '$1' as a space-delimited list
# does not decrypt any passwords
    
    echo $(ls pass/*.$gname 2>/dev/null | sed -r -e "s%^pass/%%" -e "s%\.$gname$%%" | tr ' ' '\n' | sort -u)
}

function list-password-groups {
    pname=$1
# prints all the groups that '$1' belongs to as a space-delimited list
    
    echo $(ls pass/$pname.* 2>/dev/null | sed -r "s%^pass/$pname\.%%" | tr ' ' '\n' | sort -u)
}

function list-group-users {
    gname=$1
# prints all the users that belong to '$1' as a space-delimited list

    echo $(ls group/$gname.* 2>/dev/null | sed -r "s%^group/$gname\.%%" | tr ' ' '\n' | sort -u)
}

function list-passwords {
# prints all the passwords stored in the system
# does not decrypt any passwords, only prints identifiers
    echo $(ls pass/ | sed -r -e "s%^pass/%%" -e "s%.[^.]+$%%" | tr ' ' '\n' | sort -u)
}

function list-users {
    echo $(ls user/ | sed -r -e "s%^user/%%" -e "s%.[^.]+$%%" | tr ' ' '\n' | sort -u)
}

function list-groups {
    echo $(ls group/ | sed -r -e "s%^group/%%" -e "s%.[^.]+$%%" | tr ' ' '\n' | sort -u)
}

function list-available {
    uname=$1
# prints all the password files that '$1' has access to as a space-delimited list
# does not decrypt any passwords

    groups=$(list-user-groups $uname)
    
    for gname in $groups
    do
	passes=$passes" "$(list-group-passes $gname)
    done

    echo $(echo $passes | tr ' ' '\n' | sort -u)
}

function show-pass {
    uname=$1
    utoken=$2
    pname=$3
# decrypts and prints '$3', using '$2' belonging to '$1'
# if '$1' cannot access '$3', an error is returned

    ugroups=$(list-user-groups $uname)
    pgroups=$(list-password-groups $pname)

    for group in $pgroups
    do
	echo $ugroups | grep -q $group
	if [ "$?" = "0" ]
	then
	    gtoken=$(decrypt group/$group.$uname $utoken)
	    
	    decrypt pass/$pname.$group $gtoken
	    return $?
	fi
    done
    return 1
}

function add-user {
    admintoken=$1
    uname=$2
    upass=$3
# adds '$2' to the system with '$3', authenticating with '$1'
# returns an error if the username 'admin' is supplied or the username already exists
# will NOT return an error if an invalid '$1' is supplied, because there isn't necessarily anything to validate against

    utoken=$(make-token)

    [ "$uname" = "admin" ] && return 1

    encrypt user/$uname.admin $admintoken $utoken || return 2
    encrypt user/$uname $upass $utoken || return 3
}

function change-user-pass {
    utoken=$1
    uname=$2
    newpass=$3
# changes '$2's password to '$3', authenticating with '$1'
# if the user does not belong to any groups, the password is changed without question
# otherwise, the supplied '$1' is checked against one of the groups the user belongs to
    
    testfile=$(ls group/*.$uname 2>/dev/null | tr '\n' ' ' | cut -d' ' -f1)
    [ -n "$testfile" ] && { decrypt $testfile $utoken &> /dev/null || return 1; }
    rm user/$uname
    encrypt user/$uname $newpass $utoken || return 2
	
}

function remove-user {
    admintoken=$1
    uname=$2
# removes '$2' from the system, given that '$1' is valid
# also removes all group mappings for the user
# returns an error if the user doesn't exist or '$1' is invalid
    
    decrypt user/$uname.admin $admintoken &> /dev/null|| return 2

    rm user/$uname*
    rm group/*.$uname 2>/dev/null || true
}

function make-user-admin {
    admintoken=$1
    uname=$2
# makes '$2' an administrator
# an error will be returned if '$1' is invalid

    utoken=$(decrypt user/$uname.admin $admintoken) || return 2

    encrypt group/admin.$uname $utoken $admintoken
}

function unmake-user-admin {
    admintoken=$1
    uname=$2
# revokes '$2's admin privileges
# an error is returned if the user isn't an administrator or '$1' is invalid

    decrypt user/$uname.admin $admintoken &> /dev/null || return 2

    rm group/admin.$uname
}

function map-user-group {
    admintoken=$1
    uname=$2
    gname=$3
# adds '$2' to '$3'
# admin privileges cannot be granted via this function
# an error is returned if '$3' is 'admin', '$2' already belongs to '$3', or '$1' is invalid

    [ "$gname" = "admin" ] && return 1
    [ -e group/$gname.$uname ] && return 3
    utoken=$(decrypt user/$uname.admin $admintoken) || return 4
    gtoken=$(decrypt group/$gname.admin $admintoken) || return 5

    encrypt group/$gname.$uname $utoken $gtoken
}

function unmap-user-group {
    admintoken=$1
    uname=$2
    gname=$3
# removes '$2' from '$3'
# admin privileges cannot be revoked via this function
# an error is returned if '$3' is admin, the mapping doesn't exist, or '$1' is invalid

    [ "$gname" = "admin" ] && return 2
    decrypt group/$gname.admin $admintoken &> /dev/null || return 3
    
    rm group/$gname.$uname
}

function add-group {
    admintoken=$1
    gname=$2
# adds a group called '$2'
# an error is returned if '$2' is 'admin', the group already exists, or '$1' is invalid

    [ "$gname" = "admin" ] && return 1
    [ -e group/$gname.admin ] && return 2

    gtoken=$(make-token)

    encrypt group/$gname.admin $admintoken $gtoken
}

function remove-group {
    admintoken=$1
    gname=$2
# removes the group named '$2'
# an error is returned if '$2' is 'admin', '$2' doesn't exist, or '$1' is invalid

    [ "$gname" = "admin" ] && return 1
    decrypt group/$gname.admin $admintoken &> /dev/null || return 2

    rm pass/*.$gname 2>/dev/null || true
    rm group/$gname.*
}

function map-group-pass {
    admintoken=$1
    gname=$2
    pname=$3
# adds '$3' to '$2'
# an error is returned if '$2' is 'admin', the password is already in the group, or '$1' is invalid

    [ "$gname" = "admin" ] && return 1
    [ -e pass/$pname.$gname ] && return 2
    gtoken=$(decrypt group/$gname.admin $admintoken) || return 3
    pass=$(decrypt pass/$pname.admin $admintoken) || return 4

    encrypt pass/$pname.$gname $gtoken $pass
}

function unmap-group-pass {
    admintoken=$1
    gname=$2
    pname=$3
# removes '$3' from '$2'
# returns an error if '$2' or '$3' is 'admin', the mapping doesn't exist, or '$1' is invalid

    [ "$gname" = "admin" ] && return 1
    decrypt pass/$pname.admin $admintoken &> /dev/null || return 2
    decrypt group/$gname.admin $admintoken &> /dev/null || return 3

    rm pass/$pname.$gname
}

function add-pass {
    admintoken=$1
    pname=$2
    pass=$3
# adds a password to the system. It is identified by '$2', and its value is '$3'
# an error is returned if '$1' is invalid or '$2' already exists

    encrypt pass/$pname.admin $admintoken $pass
}

function remove-pass {
    admintoken=$1
    pname=$2
# removes the password named '$2' from the system
# an error is returned if '$1' is invalid or '$2' doesn't exist

    decrypt pass/$pname.admin $admintoken &> /dev/null || return 2

    rm pass/$pname.*
}
