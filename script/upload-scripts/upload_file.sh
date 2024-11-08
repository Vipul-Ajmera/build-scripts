#!/bin/bash -e

# Check if the build is validate_build_script or wheel_build
if [[ "$VALIDATE_BUILD_SCRIPT" == "true" ]]; then
    api_key="$travis_currency_service_id_api_key" # API key for validate_build_script
    content_type="application/gzip"
    s3_url="https://s3.au-syd.cloud-object-storage.appdomain.cloud/currency-automation-toolci-bucket" # URL for validate_build_script
elif [[ "$WHEEL_BUILD" == "true" ]]; then
    api_key="$currency_ecosystem_dev_service_api_key" # API key for wheel build
    content_type="application/octet-stream"
    s3_url="https://s3.us-east.cloud-object-storage.appdomain.cloud/currency-artifacts" # URL for wheel_build
else
    echo "Error: Neither validate_build_script nor wheel_build is true."
    exit 1
fi

# Get the token request using the selected API key
token_request=$(curl -X POST https://iam.cloud.ibm.com/identity/token \
    -H "content-type: application/x-www-form-urlencoded" \
    -H "accept: application/json" \
    -d "grant_type=urn%3Aibm%3Aparams%3Aoauth%3Agrant-type%3Aapikey&apikey=$api_key")

# Check if the token request was successful based on the presence of 'errorCode'
if [[ $(echo "$token_request" | jq -r '.errorCode') == "null" ]]; then
    token=$(echo "$token_request" | jq -r '.access_token')

    # curl command for uploading the file
    response=$(curl -X PUT -H "Authorization: bearer $token" -H "Content-Type: $content_type" -T $1 "$s3_url/$PACKAGE_NAME/$VERSION/$1")

    # Check if the PUT request was successful based on the absence of an <Error> block
    if ! echo "$response" | grep -q "<Error>"; then
        echo "File successfully uploaded."
    else
        # Handle PUT request failure
        echo "Error: PUT request failed. Response: $response"
        exit 1
    fi
else
    # Handle token request failure
    echo "Error: Token request failed. Response: $token_request"
    exit 1
fi
