#!/bin/sh

krb5kdc

( while true; do
    kadmind -nofork
    sleep 5
  done) &

