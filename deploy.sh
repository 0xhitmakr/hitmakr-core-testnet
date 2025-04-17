#!/bin/bash

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Creating .env file with template values..."
    echo "PRIVATE_KEY=0xyour_private_key_here" > .env
    echo ".env file created. Please edit it with your private key before continuing."
    exit 1
fi

# Source .env file to get environment variables
source .env

# Check if PRIVATE_KEY is set and has 0x prefix
if [ "$PRIVATE_KEY" = "0xyour_private_key_here" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "Please set your PRIVATE_KEY in the .env file"
    exit 1
fi

# Ensure PRIVATE_KEY has 0x prefix
if [[ ! "$PRIVATE_KEY" == 0x* ]]; then
    echo "Adding 0x prefix to PRIVATE_KEY..."
    PRIVATE_KEY="0x$PRIVATE_KEY"
    # Update the .env file
    sed -i "s/^PRIVATE_KEY=.*/PRIVATE_KEY=$PRIVATE_KEY/" .env
    echo "Updated PRIVATE_KEY in .env file with 0x prefix"
fi

# Ask for network to deploy to
echo "Select network to deploy to:"
echo "1) Camp Testnet"
echo "2) Sepolia"
echo "3) Mainnet"
echo "4) SKALE testnet"
read -p "Enter choice (1-4): " network_choice

case $network_choice in
    1)
        NETWORK="camp_testnet"
        ;;
    2)
        NETWORK="sepolia"
        ;;
    3)
        NETWORK="mainnet"
        ;;
    4)
        NETWORK="skale_testnet"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Run the deployment script
echo "Deploying to $NETWORK..."
forge script script/DeployHitmakrCore.s.sol:DeployHitmakrCore --rpc-url $NETWORK --broadcast --verify

echo "Deployment completed!" 