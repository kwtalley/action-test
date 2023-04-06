#!/bin/bash -e

# This script stores, instantiates and executes the msgfees smart contract
PROV_CMD="provenanced"
WASM="./artifacts/msgfees.wasm"

env

# setup all of the necessary keys
"$PROV_CMD" keys add sender --keyring-backend test --testnet --hd-path "44'/1'/0'/0/0" $LOCAL_ARGS
"$PROV_CMD" keys add feebucket --keyring-backend test --testnet --hd-path "44'/1'/0'/0/0" $LOCAL_ARGS
"$PROV_CMD" keys add receiver --keyring-backend test --testnet --hd-path "44'/1'/0'/0/0" $LOCAL_ARGS

# setup key variables
export node0=$("$PROV_CMD" keys show -a validator --keyring-backend test --testnet $LOCAL_ARGS)
export sender=$("$PROV_CMD" keys show -a sender --keyring-backend test --testnet $LOCAL_ARGS)
export feebucket=$("$PROV_CMD" keys show -a feebucket --keyring-backend test --testnet $LOCAL_ARGS)
export receiver=$("$PROV_CMD" keys show -a receiver --keyring-backend test --testnet $LOCAL_ARGS)

printf "\n\nSending init coins to sender account \n\n"

"$PROV_CMD" tx bank send \
	"$node0" \
	"$sender" \
	200000000000nhash \
	--from="$node0" \
	--keyring-backend=test \
	--chain-id="testing" \
	--gas=auto \
	--gas-prices="1905nhash" \
	--gas-adjustment=1.5 \
	--broadcast-mode=block \
	--yes \
	--testnet \
	--output json $LOCAL_ARGS

printf "\n\nBinding name\n\n"
# Setup name and new COIN for the smart contract
"$PROV_CMD" tx name bind \
    "sc" \
    "$node0" \
    "pb" \
    --from="$node0" \
    --keyring-backend test \
    --chain-id="testing" \
    --gas-prices="1905nhash" \
	  --gas-adjustment=1.5 \
    --broadcast-mode block \
    --yes \
    --testnet \
	  --output json $LOCAL_ARGS

#sleep 5

printf "\n\nStoring wasm\n\n"
# Run the contract
"$PROV_CMD" tx wasm store "$WASM" \
    --instantiate-only-address "$node0" \
    --from="$node0" \
    --keyring-backend="test" \
    --chain-id="testing" \
    --gas=auto \
    --gas-prices="1905nhash" \
	  --gas-adjustment=1.5 \
    --broadcast-mode=block \
    --yes \
    -t $LOCAL_ARGS

printf "\n\nInstantiating contract\n\n"
"$PROV_CMD" tx wasm instantiate 1 '{"fee_amount":{"amount":"10000","denom":"nhash"},"fee_recipient":"'"$feebucket"'"}' \
    --admin="$node0" \
    --label="msgfees" \
    --from="$node0" \
    --keyring-backend="test" \
    --chain-id="testing" \
    --gas=auto \
    --gas-prices="1905nhash" \
	  --gas-adjustment=1.5 \
    --broadcast-mode block \
    --yes \
    --testnet $LOCAL_ARGS

# Show feebucket balance before contract execution
export feebucket_query=$("$PROV_CMD" query bank balances "$feebucket" --testnet --output json $LOCAL_ARGS)
export feebucket_denom=$(echo "$feebucket_query" | jq -r ".balances[0].denom")
export feebucket_amount=$(echo "$feebucket_query" | jq -r ".balances[0].amount")

printf "\n\nFeebucket before after contract execution: %s %s\n\n" "$feebucket_amount" "$feebucket_denom"

# Query for the contract address so we can execute it
export contract=$("$PROV_CMD" query wasm list-contract-by-code 1 -t -o json | jq -r ".contracts[0]")

printf "\n\nExecuting contract\n\n"
"$PROV_CMD" tx wasm execute \
    "$contract" \
    '{"send_funds":{"funds":{"amount":"90000","denom":"nhash"},"to_address":"'"$receiver"'"}}' \
    --amount 90000nhash \
    --from="$sender" \
    --keyring-backend test \
    --chain-id testing \
    --gas auto \
    --gas-prices="1906nhash" \
	  --gas-adjustment=1.5 \
    --broadcast-mode block \
    --yes \
    --testnet \
	  --output json $LOCAL_ARGS

# Verify that the funds were sent to the correct accounts for the receiver and the feebucket
export receiver_query=$("$PROV_CMD" query bank balances "$receiver" --testnet --output json $LOCAL_ARGS)
export receiver_denom=$(echo "$receiver_query" | jq -r ".balances[0].denom")
export receiver_amount=$(echo "$receiver_query" | jq -r ".balances[0].amount")

if [ "$receiver_denom" != "nhash" ]; then
  exit 1
fi

if [ "$receiver_amount" != "90000" ]; then
  exit 1
fi

export feebucket_query=$("$PROV_CMD" query bank balances "$feebucket" --testnet --output json $LOCAL_ARGS)
export feebucket_denom=$(echo "$feebucket_query" | jq -r ".balances[0].denom")
export feebucket_amount=$(echo "$feebucket_query" | jq -r ".balances[0].amount")

if [ "$feebucket_denom" != "nhash" ]; then
  exit 1
fi

if [ "$feebucket_amount" != "10000" ]; then
  exit 1
fi

# Show feebucket balance after contract execution
printf "\n\nFeebucket balance after contract execution: %s %s\n\n" "$feebucket_amount" "$feebucket_denom"

printf "\n\nAll good!\n"
