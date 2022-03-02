#  expectValue = "StackId"
#  scriptTimeout = 10
#  replayEnabled = false
#  replayTimeout = 0


bucket_name=`echo <STACK NAME>|cut -c -60|tr '[:upper:]' '[:lower:]'| sed 's:-*$::'`
echo "bucket_name=$bucket_name"

# update this path once we move to a separate repo
artifact_location=$(cat /$PWD/examples/failover/failover.yaml | yq -r .Parameters.artifactLocation.Default)
echo "artifact_location=$artifact_location"

if [[ '<NUMBER SUBNETS>' == '4' && '<PROVISION EXAMPLE APP>' == 'false' ]]; then
    # This is 3 nic case with no public IP
    mgmtAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 2)
    extAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 4)
    intAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 3)
    mgmtAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 2)
    extAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 4)
    intAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 3)
else
    # This is 3 nic case with public ip
    mgmtAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 2)
    extAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 1)
    intAz1=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsA").OutputValue' | cut -d ',' -f 3)
    mgmtAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 2)
    extAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 1)
    intAz2=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="subnetsB").OutputValue' | cut -d ',' -f 3)
fi
vpcId=$(aws cloudformation describe-stacks --region <REGION> --stack-name <NETWORK STACK NAME> | jq  -r '.Stacks[0].Outputs[] | select(.OutputKey=="vpcId").OutputValue')
runtimeConfig01='"<RUNTIME INIT CONFIG 01>"'
runtimeConfig02='"<RUNTIME INIT CONFIG 02>"'
secret_name=$(aws secretsmanager describe-secret --secret-id <DEWPOINT JOB ID>-secret-runtime --region <REGION> | jq -r .Name)
secret_arn=$(aws secretsmanager describe-secret --secret-id <DEWPOINT JOB ID>-secret-runtime --region <REGION> | jq -r .ARN)

region=$(aws s3api get-bucket-location --bucket $bucket_name | jq -r .LocationConstraint)

if [ -z $region ] || [ $region == null ]; then
    region="us-east-1"
    echo "bucket region:$region"
else
    echo "bucket region:$region"
fi

if [[ "<LICENSE TYPE>" == "byol" ]]; then
    regKey01='<AUTOFILL EVAL LICENSE KEY>'
    regKey02='<AUTOFILL EVAL LICENSE KEY 2>'
fi

do_index=2
if [[ "<PROVISION EXAMPLE APP>" == "true" ]]; then
    do_index=3
fi

if [[ "<RUNTIME INIT CONFIG 01>" == *{* ]]; then
    config_with_added_secret_id="${runtimeConfig01/<SECRET_ID>/$secret_name}"
    config_with_added_ids="${config_with_added_secret_id/<BUCKET_ID>/$bucket_name}"
    runtimeConfig01=$config_with_added_ids
    runtimeConfig01="${runtimeConfig01/<ARTIFACT LOCATION>/$artifact_location}"


    config_with_added_secret_id="${runtimeConfig02/<SECRET_ID>/$secret_name}"
    config_with_added_ids="${config_with_added_secret_id/<BUCKET_ID>/$bucket_name}"
    runtimeConfig02=$config_with_added_ids
    runtimeConfig02="${runtimeConfig02/<ARTIFACT LOCATION>/$artifact_location}"
else
    if [[ "<PROVISION EXAMPLE APP>" == "false" ]]; then
        declare -a runtime_init_config_files=(/$PWD/examples/failover/bigip-configurations/runtime-init-conf-3nic-<LICENSE TYPE>-instance01.yaml /$PWD/examples/failover/bigip-configurations/runtime-init-conf-3nic-<LICENSE TYPE>-instance02.yaml)
    else
        declare -a runtime_init_config_files=(/$PWD/examples/failover/bigip-configurations/runtime-init-conf-3nic-<LICENSE TYPE>-instance01-with-app.yaml /$PWD/examples/failover/bigip-configurations/runtime-init-conf-3nic-<LICENSE TYPE>-instance02-with-app.yaml)
    fi
    counter=1
    for config_path in "${runtime_init_config_files[@]}"; do
        # Modify Runtime-init, then upload to s3.
        cp -avr $config_path <DEWPOINT JOB ID>-0$counter.yaml

        # Create user for login tests
        /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.admin.class = \"User\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.admin.password = \"{{{BIGIP_PASSWORD}}}\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.admin.shell = \"bash\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.admin.userType = \"regular\"" -i <DEWPOINT JOB ID>-0$counter.yaml

        /usr/bin/yq e ".extension_services.service_operations.[${do_index}].value.Common.admin.class = \"User\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[${do_index}].value.Common.admin.password = \"{{{BIGIP_PASSWORD}}}\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[${do_index}].value.Common.admin.shell = \"bash\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[${do_index}].value.Common.admin.userType = \"regular\"" -i <DEWPOINT JOB ID>-0$counter.yaml

        # Disable AutoPhoneHome
        /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.My_System.autoPhonehome = false" -i <DEWPOINT JOB ID>-0$counter.yaml
        /usr/bin/yq e ".extension_services.service_operations.[${do_index}].value.Common.My_System.autoPhonehome = false" -i <DEWPOINT JOB ID>-0$counter.yaml

        # Runtime parameters
        /usr/bin/yq e ".runtime_parameters.[0].secretProvider.secretId = \"$secret_name\"" -i <DEWPOINT JOB ID>-0$counter.yaml

        if [[ "<LICENSE TYPE>" == "byol" ]]; then
            # Add BYOL License to declaration
            if [[ $counter == 1 ]]; then
                /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.My_License.regKey = \"$regKey01\"" -i <DEWPOINT JOB ID>-0$counter.yaml
            else
                /usr/bin/yq e ".extension_services.service_operations.[0].value.Common.My_License.regKey = \"$regKey02\"" -i <DEWPOINT JOB ID>-0$counter.yaml
            fi
        fi

        if [[ "<PROVISION EXAMPLE APP>" == "true" ]]; then
            /usr/bin/yq e ".extension_services.service_operations.[2].value.Tenant_1.Shared.Custom_WAF_Policy.url = \"https://cdn.f5.com/product/cloudsolutions/solution-scripts/Rapid_Deployment_Policy_13_1.xml\"" -i <DEWPOINT JOB ID>-0$counter.yaml
        fi

        # print out config file
        /usr/bin/yq e <DEWPOINT JOB ID>-0$counter.yaml

        # update copy
        cp <DEWPOINT JOB ID>-0$counter.yaml update_<DEWPOINT JOB ID>-0$counter.yaml

        # upload to s3
        aws s3 cp --region <REGION> update_<DEWPOINT JOB ID>-0$counter.yaml s3://"$bucket_name"/examples/failover/bigip-configurations/update_<DEWPOINT JOB ID>-0$counter.yaml --acl public-read
        aws s3 cp --region <REGION> <DEWPOINT JOB ID>-0$counter.yaml s3://"$bucket_name"/examples/failover/bigip-configurations/<DEWPOINT JOB ID>-0$counter.yaml --acl public-read

        ((counter=counter+1))
    done
fi

# Set Parameters using file to eiliminate issues when passing spaces in parameter values
cat <<EOF > parameters.json
[
    {
        "ParameterKey": "artifactLocation",
        "ParameterValue": "$artifact_location"
    },
    {
        "ParameterKey": "application",
        "ParameterValue": "f5-app-<DEWPOINT JOB ID>"
    },
    {
        "ParameterKey": "bigIpCustomImageId",
        "ParameterValue": "<CUSTOM IMAGE ID>"
    },
    {
        "ParameterKey": "bigIpImage",
        "ParameterValue": "<BIGIP IMAGE>"
    },
    {
        "ParameterKey": "bigIpInstanceType",
        "ParameterValue": "<BIGIP INSTANCE TYPE>"
    },
    {
        "ParameterKey": "bigIpRuntimeInitConfig01",
        "ParameterValue": $runtimeConfig01
    },
    {
        "ParameterKey": "bigIpRuntimeInitConfig02",
        "ParameterValue": $runtimeConfig02
    },
    {
        "ParameterKey": "bigIpRuntimeInitPackageUrl",
        "ParameterValue": "<BIGIP RUNTIME INIT PACKAGEURL>"
    },
    {
        "ParameterKey": "bigIpPeerAddr",
        "ParameterValue": "<BIGIP PEER ADDR>"
    },
    {
        "ParameterKey": "bigIpMgmtSubnetId01",
        "ParameterValue": "$mgmtAz1"
    },
    {
        "ParameterKey": "bigIpMgmtSubnetId02",
        "ParameterValue": "$mgmtAz2"
    },
    {
        "ParameterKey": "bigIpExternalSubnetId01",
        "ParameterValue": "$extAz1"
    },
    {
        "ParameterKey": "bigIpExternalSubnetId02",
        "ParameterValue": "$extAz2"
    },
    {
        "ParameterKey": "bigIpInternalSubnetId01",
        "ParameterValue": "$intAz1"
    },
    {
        "ParameterKey": "bigIpInternalSubnetId02",
        "ParameterValue": "$intAz2"
    },
    {
        "ParameterKey": "provisionPublicIpMgmt",
        "ParameterValue": "<PROVISION MGMT PUBLIC IP>"
    },
    {
        "ParameterKey": "provisionPublicIpVip",
        "ParameterValue": "<PROVISION EXAMPLE APP>"
    },
    {
        "ParameterKey": "restrictedSrcAddressApp",
        "ParameterValue": "0.0.0.0/0"
    },
    {
        "ParameterKey": "restrictedSrcAddressMgmt",
        "ParameterValue": "0.0.0.0/0"
    },
    {
        "ParameterKey": "cfeS3Bucket",
        "ParameterValue": "bigip-ha-solution-<DEWPOINT JOB ID>"
    },
    {
        "ParameterKey": "s3BucketName",
        "ParameterValue": "$bucket_name"
    },
    {
        "ParameterKey": "s3BucketRegion",
        "ParameterValue": "$region"
    },
    {
        "ParameterKey": "secretArn",
        "ParameterValue": "$secret_arn"
    },
    {
        "ParameterKey": "sshKey",
        "ParameterValue": "<SSH KEY>"
    },
    {
        "ParameterKey": "uniqueString",
        "ParameterValue": "<UNIQUESTRING>"
    },
    {
        "ParameterKey": "vpcId",
        "ParameterValue": "$vpcId"
    },
    {
        "ParameterKey": "vpcCidr",
        "ParameterValue": "<CIDR>"
EOF
if [[ "<PROVISION EXAMPLE APP>" == "false" ]]; then
cat <<EOF >> parameters.json
    },
    {
        "ParameterKey": "bigIpExternalSelfIp01",
        "ParameterValue": "10.0.3.11"
    },
    {
        "ParameterKey": "bigIpExternalVip01",
        "ParameterValue": "10.0.3.101"
    },
    {
        "ParameterKey": "bigIpExternalSelfIp02",
        "ParameterValue": "10.0.7.11"
    },
    {
        "ParameterKey": "bigIpExternalVip02",
        "ParameterValue": "10.0.7.101"
    },
    {
        "ParameterKey": "bigIpInternalSelfIp02",
        "ParameterValue": "10.0.6.11"
    },
    {
        "ParameterKey": "bigIpMgmtSelfIp02",
        "ParameterValue": "10.0.5.11"
    }
]
EOF
else
cat <<EOF >> parameters.json
    }
]
EOF
fi
cat parameters.json

aws cloudformation create-stack --disable-rollback --region <REGION> --stack-name <STACK NAME> --tags Key=creator,Value=dewdrop Key=delete,Value=True \
--template-url https://s3.amazonaws.com/"$bucket_name"/<TEMPLATE NAME> \
--capabilities CAPABILITY_IAM \
--parameters file://parameters.json