# Usage
```
bash make_configs.sh N [ip1:port1,ip2:port2...] [config_mixin.json] [--bind0]
```
where:
 - N - number of nodes
 - ip1:port1,... - comma-separated list of ips and base ports (optional, defaults to 127.0.0.1:1234,127.0.0.2:1234...)
 - config_mixin.json - config to merge with the common `config0.json` (optional)
 - `--bind0` - if need to bind to 0.0.0.0, and not a specisifed IP address (optional)

Influental environment variables:
 - `SGX_URL`
 - `CERTS_PATH` - path to SGX certificates, default /skale_node_data/sgx_certs

Influental files:
 - `config0.json` contains common options that will be overridden by individual nodes' options and `config_mixin.json`
 - `uniq.txt` - is generated on each invocation, and if present in the current directory, will be used to not re-generate BLS keys.

If run with `SGX_URL` then will generate configs with BLS keys present. If no `SGX_URL`, BLS will be turned off.

### Output
 - `config1.json`
 - `config2.json`
 - ...
 - `configN.json`
