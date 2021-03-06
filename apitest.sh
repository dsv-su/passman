#!/bin/bash

set -e

# Import functions
. cryptapi.sh

echo "########################## STARTING ##########################"

echo "Cleaning up..."
rm -rf user
rm -rf group
rm -rf pass
echo "done."

echo "Bootstrapping..."
bootstrap ua uapass
admintoken=$(validate-admin ua $(validate-user ua uapass))
echo "done."

echo "Creating passwords..."
for i in $(seq 5)
do
    add-pass $admintoken "p${i}" "pass${i}" || exit $?
done
echo "done."

echo "Creating groups..."
for i in $(seq 3)
do
    add-group $admintoken g${i} || exit $?
done
echo "done."

echo "Creating users..."
for i in $(seq 5)
do
    echo "u${i} u${i}pass"
    add-user $admintoken u${i} u${i}pass || exit $?
done
echo "done."

echo "Mapping groups to passwords..."
map-group-pass $admintoken g1 p1 || exit $?
map-group-pass $admintoken g1 p2 || exit $?
map-group-pass $admintoken g1 p3 || exit $?
map-group-pass $admintoken g2 p2 || exit $?
map-group-pass $admintoken g3 p3 || exit $?
map-group-pass $admintoken g3 p4 || exit $?
echo "done."

echo "Mapping users to groups..."
map-user-group $admintoken u1 g1 || exit $?
map-user-group $admintoken u1 g2 || exit $?
map-user-group $admintoken u2 g2 || exit $?
map-user-group $admintoken u2 g3 || exit $?
map-user-group $admintoken u3 g2 || exit $?
map-user-group $admintoken u4 g3 || exit $?
map-user-group $admintoken u5 g1 || exit $?
map-user-group $admintoken u5 g3 || exit $?
echo "done."

echo
echo "user/*:"
ls user/*

echo
echo "group/*:"
ls group/*

echo
echo "pass/*:"
ls pass/*

echo "Running tests:"
echo
echo "show-avail"
list-available u2 || exit $?

echo
echo "show-user-groups"
list-user-groups u3 || exit $?

echo
echo "show-password-groups"
list-password-groups p2 || exit $?

echo
echo "show-group-passes"
list-group-passes g1 || exit $?

echo
echo "decrypt"
token=$(decrypt user/u1 u1pass) || exit $?

echo
echo "show-pass"
show-pass u1 $token p1 || exit $?

echo
echo "show-pass"
show-pass u1 $token p2 || exit $?

echo
echo "show-pass"
show-pass u1 $token p5 && exit $?

echo "########################## FINISHED ##########################"
