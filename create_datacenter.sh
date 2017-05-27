#!/bin/bash


## Set up environment and programmatic access.

export AWS_ACCESS_KEY_ID=AKIAJ2AVL6LCLE5WP53A
export AWS_SECRET_ACCESS_KEY=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
export AWS_DEFAULT_OUTPUT=text
export AWS_DEFAULT_REGION=us-east-1


## Create a load-balanced pool of how many nodes?

inputArg=$1

if [[ "$inputArg" =~ ^-?[0-9]+[.,]?[0-9]*$ ]]
then


## Create new VPC

echo "$(tput setaf 1) Creating VPC. $(tput sgr 0)"

export vpcId=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text`
aws ec2 create-tags --resources $vpcId --tags Key=Name,Value=MyNewVPC

sleep 5

echo New VPC $vpcId created.


## Create Public and Private subnets in different availability zones

export publicSubnetAID=`aws ec2 create-subnet --vpc-id $vpcId --availability-zone us-east-1a --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text`
aws ec2 modify-subnet-attribute --subnet-id $publicSubnetAID --map-public-ip-on-launch
aws ec2 create-tags --resources $publicSubnetAID --tags Key=Name,Value=NewVPCPublicSubnet

echo New public subnet $publicSubnetAID created.

export publicSubnetBID=`aws ec2 create-subnet --vpc-id $vpcId --availability-zone us-east-1b --cidr-block 10.0.2.0/24 --query 'Subnet.SubnetId' --output text`
aws ec2 modify-subnet-attribute --subnet-id $publicSubnetBID --map-public-ip-on-launch
aws ec2 create-tags --resources $publicSubnetBID --tags Key=Name,Value=NewVPCPublicSubnet2

echo New public subnet $publicSubnetBID created.

export privateSubnetID=`aws ec2 create-subnet --vpc-id $vpcId --availability-zone us-east-1c --cidr-block 10.0.3.0/24 --query 'Subnet.SubnetId' --output text`
aws ec2 create-tags --resources $privateSubnetID --tags Key=Name,Value=NewVPCPrivateSubnet

echo New private subnet $privateSubnetID created.


## Create and attach internet gateway to VPC and public subnets

export newInternetGate=`aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text`
aws ec2 create-tags --resources $newInternetGate --tags Key=Name,Value=NewInternetGate
aws ec2 attach-internet-gateway --vpc-id $vpcId --internet-gateway-id $newInternetGate

echo New internet gateway $newInternetGate created and attached to VPC $vpcId.

export newRouteTable=`aws ec2 create-route-table --vpc-id $vpcId --query 'RouteTable.RouteTableId' --output text`
aws ec2 create-tags --resources $newRouteTable --tags Key=Name,Value=NewPublicRoute
aws ec2 create-route --route-table-id $newRouteTable --destination-cidr-block 0.0.0.0/0 --gateway-id $newInternetGate

echo New public route table $newRouteTable created.


## Associate new PUBLIC subnets with new public route

aws ec2 associate-route-table --subnet-id $publicSubnetAID --route-table-id $newRouteTable
aws ec2 associate-route-table --subnet-id $publicSubnetBID --route-table-id $newRouteTable


## Create new webDMZ security group to launch new EC2 instances into

export newSecurityGroupID=`aws ec2 create-security-group --vpc-id $vpcId --group-name newWebDMZ --description "new web DMZ" `
aws ec2 create-tags --resources $newSecurityGroupID --tags Key=Name,Value=newWebDMZ

echo New web security group $newSecurityGroupID created.


## Specify security group rules

aws ec2 authorize-security-group-ingress --group-id $newSecurityGroupID --protocol icmp --port -1 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $newSecurityGroupID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $newSecurityGroupID --protocol tcp --port 22 --cidr 0.0.0.0/0


## Launch ($inputArg) number of EC2 instances into alternating public-facing subnets (Availability Zones)

echo Creating instances.

for ((i=$1;i>=1;i--)); 
	do 
		if [ $((i%2)) -eq 0 ];
			then
    			aws ec2 run-instances --instance-type t2.micro --subnet-id $publicSubnetAID --image-id ami-c58c1dd3  --security-group-id $newSecurityGroupID  --associate-public-ip-address;
			else
    			aws ec2 run-instances --instance-type t2.micro --subnet-id $publicSubnetBID --image-id ami-c58c1dd3  --security-group-id $newSecurityGroupID  --associate-public-ip-address;
    	fi
	done
	

## Create an array of the new instance_ids

Node_Array=( `aws ec2 describe-instances --filters "Name=instance-state-code,Values=0" --query Reservations[*].Instances[*].[InstanceId] --output text` )

echo Here are your new instance IDs:

for node_id in "${Node_Array[@]}"
do
   echo "${node_id}"
done


## Test that instance state code = 16 (running) for each.

echo Waiting for each instance to be marked running.

for node_id in "${Node_Array[@]}"
do
	while [[ `aws ec2 describe-instance-status --instance-id $node_id --query InstanceStatuses[*].[InstanceState.Code] --output text` != 16 ]]
		do
			echo NR > /dev/null
		done
done

echo All instances are now running.


	
## Create new load balancer and add the new instances to it.

aws elb create-load-balancer --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" --load-balancer-name newPublicELB --subnets $publicSubnetAID $publicSubnetBID  --security-groups $newSecurityGroupID

echo "$(tput setaf 1)New Elastic Load Balancer created. $(tput sgr 0)"

for node_id in "${Node_Array[@]}"
do
	aws elb register-instances-with-load-balancer --load-balancer-name newPublicELB --instances $node_id;
	echo "${node_id}" registered with load balancer.
done


## ** NEED TO ADD IN CODE FOR MONITORING HERE ** ##

	
	else
    echo Input must be an integer which specifies the number of nodes to launch.
fi









