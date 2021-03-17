#!/bin/bash

#input: keysN.json, SGX server, and schain unique id
# output keys imported to SGX server and ecdsaI.json 

set -x

N=$1        # num nodes
uniq=$2     # uniq schain id
SGX_URL=$3
CERTS_PATH=$4

ORIG_CWD="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

for i in $( seq 0 $((N-1)) )
do
    dec=$( jq -r ".privateKey[\"$i\"]" keys$N.json )
    hex=$( echo "obase=16;$dec" | bc )
    
    curl --cert $CERTS_PATH/sgx.crt --key $CERTS_PATH/sgx.key -X POST --data '{"id":1, "jsonrpc":"2.0","method":"importBLSKeyShare","params":{"keyShareName":"BLS_KEY:SCHAIN_ID:'$uniq':NODE_ID:'$((i+1))':DKG_ID:0","keyShare":"0x'$hex'"}}' -H 'content-type:application/json;' $SGX_URL -k
    curl --cert $CERTS_PATH/sgx.crt --key $CERTS_PATH/sgx.key -X POST --data '{"id":1, "jsonrpc":"2.0","method":"generateECDSAKey","params":{}}' -H 'content-type:application/json;' $SGX_URL -k >ecdsa$((i+1)).json
done

cd "$ORIG_CWD"