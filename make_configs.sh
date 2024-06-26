#!/bin/bash

# params:
# $1 N - number of nodes
# $2 ip:port,... - comma-separated list of ips and base ports (optional)
# $3 config_mixin - config to merge with common one (optional)
# --bind0 - if need to bind to 0.0.0.0, and not a specisifed IP address
# --historic ip:port - where will historic node listen
# --sync ip:port - where sync node wil listen
# SGX_URL
# CERTS_PATH - path to SGX certificates, default /skale_node_data/sgx_certs

# output:
# config1.json ... configN.json
# config-historic.json
# config-sync.json

# uniq.txt caches schain id for SGX server

N=$1
IFS=',' read -r -a IPS <<< "$2"
config_mixin=""

if [ "$3" != "" ]
then
  config_mixin=$(realpath "$3")
fi

BIND0=false
if [[ "$@" == *"--bind0"* ]]
then
  BIND0=true
fi

HISTORIC=( $( echo "$@" | grep -oP "\--historic (\S+)" ) )
HISTORIC=${HISTORIC[1]}

SYNC=( $( echo "$@" | grep -oP "\--sync (\S+)" ) )
SYNC=${SYNC[1]}

ORIG_CWD="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

for I in $( seq 0 $((N-1)) ); do
    IPS[$I]=${IPS[$I]:-127.0.0.$((I+1)):$((1231+I*10))}
done

echo "IPS="${IPS[*]}
echo "SGX_URL=$SGX_URL"

if [ ! -z "$SGX_URL" ]
then
    CERTS_PATH=${CERTS_PATH:-/skale_node_data/sgx_certs}
    if [ ! -f ${ORIG_CWD}/uniq.txt ]
    then
        uniq=$(date +%s)
	echo "Preparing SGX keys"
        ./sgx/prepare_keys.sh $N $uniq $SGX_URL "$CERTS_PATH"
        echo $uniq >${ORIG_CWD}/uniq.txt
    else
	echo "Found existing SGX keys via ${ORIG_CWD}/uniq.txt"
    fi
fi

echo -- Prepare config --

echo '{ "skaleConfig": {"sChain": { ' > _nodes.json 
#if [[ ! -z "$SGX_URL" && -z "$( python3 config.py extract $config_mixin skaleConfig.sChain.snapshotIntervalSec )" ]]
#then
#    echo '"snapshotIntervalSec": 60,'  >> _nodes.json
#fi
echo '"nodes": [' >> _nodes.json

I=0
for E in ${IPS[*]}
do

    IFS=':' read -r -a arr <<< "$E"
    IP=${arr[0]}
    PORT=${arr[1]:-1231}

	I=$((I+1))

	if [ ! -z "$SGX_URL" ]
	then
	    if [ -f "sgx/keys$N.json" ]
	    then
		echo "Reading SGX keys from sgx/keys$N.json"
	    else
		echo "Error reading sgx/keys$N.json"
		exit 1
	    fi
        read -r -d '' NODE_CFG <<- ****
        {
            "nodeID": $I,
            "ip": "$IP",
            "basePort": $PORT,
            "schainIndex" : $I,
            "publicKey":"0x$(echo $(jq '.result.publicKey' sgx/ecdsa$I.json) | xargs echo)",
            "blsPublicKey0": $(jq '.BLSPublicKey["'$((I-1))'"]["0"]' sgx/keys$N.json),
            "blsPublicKey1": $(jq '.BLSPublicKey["'$((I-1))'"]["1"]' sgx/keys$N.json),
            "blsPublicKey2": $(jq '.BLSPublicKey["'$((I-1))'"]["2"]' sgx/keys$N.json),
            "blsPublicKey3": $(jq '.BLSPublicKey["'$((I-1))'"]["3"]' sgx/keys$N.json)
        }
****
    else
	echo "Generating no-SGX config"
        read -r -d '' NODE_CFG <<- ****
        {
            "nodeID": $I,
            "ip": "$IP",
            "basePort": $PORT,
            "schainIndex" : $I,
            "publicKey":""
        }
****
    fi

	echo "$NODE_CFG" >> _nodes.json

	if [[ "$I" != "$N" ]]; then
		echo "," >>_nodes.json
	fi

done

echo "]" >> _nodes.json

if [ ! -z "$SGX_URL" ]
then
echo "Preparing nodeGroups"
echo ',"nodeGroups": { "0": { "nodes": {' >> _nodes.json
I=0
for E in ${IPS[*]}
do

    IFS=':' read -r -a arr <<< "$E"
    IP=${arr[0]}
    PORT=${arr[1]:-1231}

	I=$((I+1))

        read -r -d '' ITEM <<- ****
	"$I":
        [   $((I-1)),
            $I,
            "0x$(echo $(jq '.result.publicKey' sgx/ecdsa$I.json) | xargs echo)"
        ]
****

echo "$ITEM" >> _nodes.json
if [[ "$I" != "$N" ]]; then
	echo "," >>_nodes.json
fi

done
echo "}," >> _nodes.json

read -r -d '' BLS <<- ****
"bls_public_key": {
    "blsPublicKey0": $(jq '.commonBLSPublicKey["0"]' sgx/keys$N.json),
    "blsPublicKey1": $(jq '.commonBLSPublicKey["1"]' sgx/keys$N.json),
    "blsPublicKey2": $(jq '.commonBLSPublicKey["2"]' sgx/keys$N.json),
    "blsPublicKey3": $(jq '.commonBLSPublicKey["3"]' sgx/keys$N.json)
}
****

echo "$BLS" >> _nodes.json

echo "} }" >> _nodes.json
fi # if SGX_URL

echo "} } }" >> _nodes.json

python3 config.py merge config0.json $config_mixin _nodes.json >config.json
rm _nodes.json

I=0
for E in ${IPS[*]}
do
    IFS=':' read -r -a arr <<< "$E"
    IP=${arr[0]}
    PORT=${arr[1]:-1231}

	I=$((I+1))

        BINDIP=$IP
        if $BIND0
        then
          BINDIP='0.0.0.0'
        fi

	if [ ! -z "$SGX_URL" ]
	then
        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Node$I",
                            "nodeID": $I,
                            "bindIP": "$BINDIP",
                            "basePort": $PORT,
                            "enable-debug-behavior-apis": true,
                            "ecdsaKeyName": $(jq '.result.keyName' sgx/ecdsa$I.json),
                               "wallets": {
                                    "ima": {
                                     "url": "$SGX_URL",
                                     "keyShareName": "BLS_KEY:SCHAIN_ID:$(cat ${ORIG_CWD}/uniq.txt):NODE_ID:$I:DKG_ID:0",
                                     "t": 3,
                                     "n": 4,
                                     "BLSPublicKey0": $(jq '.BLSPublicKey["'$((I-1))'"]["0"]' sgx/keys$N.json),
                                     "BLSPublicKey1": $(jq '.BLSPublicKey["'$((I-1))'"]["1"]' sgx/keys$N.json),
                                     "BLSPublicKey2": $(jq '.BLSPublicKey["'$((I-1))'"]["2"]' sgx/keys$N.json),
                                     "BLSPublicKey3": $(jq '.BLSPublicKey["'$((I-1))'"]["3"]' sgx/keys$N.json),
                                     "commonBLSPublicKey0": $(jq '.commonBLSPublicKey["0"]' sgx/keys$N.json),
                                     "commonBLSPublicKey1": $(jq '.commonBLSPublicKey["1"]' sgx/keys$N.json),
                                     "commonBLSPublicKey2": $(jq '.commonBLSPublicKey["2"]' sgx/keys$N.json),
                                     "commonBLSPublicKey3": $(jq '.commonBLSPublicKey["3"]' sgx/keys$N.json)
                                    }
                                }
                }
            }
        }
****
    else
        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Node$I",
                            "nodeID": $I,
                            "bindIP": "$BINDIP",
                            "basePort": $PORT,
                            "ecdsaKeyName": "",
                            "enable-debug-behavior-apis": true
                }
            }
        }
****
    fi

	echo "$NODE_INFO" > _node_info.json

	python3 config.py merge config.json _node_info.json >${ORIG_CWD}/config$I.json
done

if [[ ! -z "$HISTORIC" ]]
then

    IFS=':' read -r -a arr <<< "$HISTORIC"
    IP=${arr[0]}
    PORT=${arr[1]:-1231}

    if $BIND0
    then
        IP='0.0.0.0'
    fi

    if [ ! -z "$SGX_URL" ]
	then

        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Historic",
                            "nodeID": 100,
                            "bindIP": "$IP",
                            "basePort": $PORT,
                            "ecdsaKeyName": "",
                            "enable-debug-behavior-apis": true,
                            "syncNode": true,
                            "archiveMode": true,
                            "syncFromCatchup": true,
                            "ecdsaKeyName": $(jq '.result.keyName' sgx/ecdsa$I.json),
                               "wallets": {
                                    "ima": {
                                     "n": 4,
                                     "commonBLSPublicKey0": $(jq '.commonBLSPublicKey["0"]' sgx/keys$N.json),
                                     "commonBLSPublicKey1": $(jq '.commonBLSPublicKey["1"]' sgx/keys$N.json),
                                     "commonBLSPublicKey2": $(jq '.commonBLSPublicKey["2"]' sgx/keys$N.json),
                                     "commonBLSPublicKey3": $(jq '.commonBLSPublicKey["3"]' sgx/keys$N.json)
                                    }
                                }
                }
            }
        }
****
    else

        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Historic",
                            "nodeID": 100,
                            "bindIP": "$IP",
                            "basePort": $PORT,
                            "ecdsaKeyName": "",
                            "enable-debug-behavior-apis": true,
                            "syncNode": true,
                            "archiveMode": true,
                            "testSignatures": true
                }
            }
        }
****
    fi

	echo "$NODE_INFO" > _node_info.json
	python3 config.py merge config.json _node_info.json >${ORIG_CWD}/config-historic.json
fi

if [[ ! -z "$SYNC" ]]
then

    IFS=':' read -r -a arr <<< "$SYNC"
    IP=${arr[0]}
    PORT=${arr[1]:-1231}

    if $BIND0
    then
        IP='0.0.0.0'
    fi

    if [ ! -z "$SGX_URL" ]
	then

        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Sync",
                            "nodeID": 100,
                            "bindIP": "$IP",
                            "basePort": $PORT,
                            "ecdsaKeyName": "",
                            "enable-debug-behavior-apis": true,
                            "syncNode": true,
                            "archiveMode": false,
                            "ecdsaKeyName": $(jq '.result.keyName' sgx/ecdsa$I.json),
                               "wallets": {
                                    "ima": {
                                     "n": 4,
                                     "commonBLSPublicKey0": $(jq '.commonBLSPublicKey["0"]' sgx/keys$N.json),
                                     "commonBLSPublicKey1": $(jq '.commonBLSPublicKey["1"]' sgx/keys$N.json),
                                     "commonBLSPublicKey2": $(jq '.commonBLSPublicKey["2"]' sgx/keys$N.json),
                                     "commonBLSPublicKey3": $(jq '.commonBLSPublicKey["3"]' sgx/keys$N.json)
                                    }
                                }
                }
            }
        }
****
    else

        read -r -d '' NODE_INFO <<- ****
        {
            "skaleConfig": {
                "nodeInfo": {
                            "nodeName": "Sync",
                            "nodeID": 101,
                            "bindIP": "$IP",
                            "basePort": $PORT,
                            "ecdsaKeyName": "",
                            "enable-debug-behavior-apis": true,
                            "syncNode": true,
                            "archiveMode": false,
                            "testSignatures": true
                }
            }
        }
****
    fi

	echo "$NODE_INFO" > _node_info.json
	python3 config.py merge config.json _node_info.json >${ORIG_CWD}/config-sync.json
fi

set -x

rm _node_info.json

cd "$ORIG_CWD"
