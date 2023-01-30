#!/bin/bash
######################################################################
## (C)Copyright 2023 Hewlett Packard Enterprise Development LP
######################################################################
######################################################################
# SWARM LEARNING SCRIPT TO TAKE LOGS.
# The tar archive includes
#   => Output of swarmLogCollector.sh script [OS info, nvidia-smi, docker ps -a] 
#	=>  Docker logs from all Swarm artifacts: [SN, SWOP, SWCI, SL, ML]
#########################################################################
#set -x #Debug ON

#Method to exit log collection if user did not pass arguments properly.
exitLogCollection(){
  echo -e "$@"
  exit 1
}

usage='\nUSAGE:\n
if using SWOP:\n
./swarmLogCollector.sh "<DOCKER_HUB>" "workspace=<swarm-learning/workspace/exampleFolder>"\n
if using run-sl:\n
./swarmLogCollector.sh "<DOCKER_HUB>" "mlimage=<ML Image Name>"\n

EXAMPLES:\n
./swarmLogCollector.sh "hub.myenterpriselicense.hpe.com/hpe_eval/swarm-learning" "workspace=/opt/hpe/swarm-learning/workspace/fraud-detection/"\n

./swarmLogCollector.sh "hub.myenterpriselicense.hpe.com/hpe_eval/swarm-learning" "mlimage=user-env-tf2.7.0-swop"\n'

#Checking docker hub passed as argument. If not, exiting
if [ -z "$1" ]
  then
    msg=`date`"-ERROR: DOCKER HUB ARGUMENT IS EMPTY..Exiting!!" 
    exitLogCollection $msg $usage
fi

#Checking absolute installation path or ml image path passed as argument. If not, exiting
if [ -z "$2" ]
  then
    msg=`date`"-ERROR: You have to provide absolute path to workspace(if using SWOP to running examples or ML Image name (If using run SL script) !!"
    exitLogCollection $msg $usage
fi

hostname=$(hostname)
dt=$(date +%Y%m%d%H%M%S)

LOG_DIR="swarm_logs_$hostname_$dt"

#Creating dir for saving logs 
mkdir -m 777 "$LOG_DIR"

#Checking user using SWOP or SL to run the command.
IFS='=' read -ra parse_ml_or_swop <<< $2

if [ "${parse_ml_or_swop[0]}" == "mlimage" ] ; then
  USER_CONTAINERS=${parse_ml_or_swop[1]}
elif [ "${parse_ml_or_swop[0]}" == "workspace" ] ; then
  WORKSPACE=${parse_ml_or_swop[1]}
  IFS=':' read -ra  user_container <<< $(cat $WORKSPACE/swci/taskdefs/user_env_tf_build_task.yaml | grep Outcome)
  USER_CONTAINERS_=${user_container[1]}
  USER_CONTAINERS="$(echo -e "${USER_CONTAINERS_}" | tr -d '[:space:]')"

  cp $WORKSPACE/swci/taskdefs/*.yaml "$LOG_DIR"/
  cp $WORKSPACE/swop/*.yaml "$LOG_DIR"/  
else
  msg=`date`"-ERROR: Either mlimage or workspace should be passed..Exiting!!"
  exitLogCollection $msg $usage
fi

exec > "$LOG_DIR"/out.log                                                                       
exec 2>&1

echo `date`":LOG COLLECTION STARTED:"
echo -e "\n================================================\n"

# Checking the user image exists or not 
echo "User Container is: $USER_CONTAINERS"
if [[ "$(docker images -q $USER_CONTAINERS:latest 2> /dev/null)" == "" ]]; then
  echo -e `date`"-ERROR: $USER_CONTAINERS:latest not exists\n"
fi

#Capturing output of "id"
echo -e "User permission for docker Sudo:\n"
id 
#Getting OS info
# This command will work in ubuntu and RHEL
# ######## Sample output from ubuntu  ############
# No LSB modules are available.
# Distributor ID: Ubuntu
# Description:    Ubuntu 20.04.3 LTS
# Release:        20.04
# Codename:       focal
# #########Sample output from RHEL ############
# LSB Version:    # :core-4.1-amd64:core-4.1-noarch:cxx-4.1-amd64:cxx-4.1-noarch:desktop-4.1-amd64:desktop-4.1-noarch:languages-4.1-amd64:languages-4.1-noarch:printing-4.1-amd64:printing-4.1-noarch
# Distributor ID: RedHatEnterprise
# Description:    Red Hat Enterprise Linux release 8.5 (Ootpa)
# Release:        8.5
# Codename:       Ootpa

echo -e "\nOS details:\n"
lsb_release -a

echo -e "\nDocker Version Details:\n"
docker version

echo -e "\nDocker Info:\n"
docker info

echo -e "Running and exited dockers details:\n"
docker ps -a

echo -e "NVIDIA DETAILS\n"
nvidia-smi

DOCKER_HUB=$1

# If user has multiple version of swarm, this will reurn a array.
TAGS=$(docker images | grep $DOCKER_HUB/sn  | awk '{print $2}')
tags_array=($TAGS)

#Looping through images and checking all images exists.
for TAG in "${!TAGS[@]}"
do
	for image in swop swci sn sl
	 do
		if [[ "$(docker images -q $DOCKER_HUB/$image:${tags_array[TAG]} 2> /dev/null)" == "" ]]; then
			echo `date`"-ERROR: $DOCKER_HUB/$image:${tags_array[TAG]} not exists"
		else
			echo `date`"-INFO: $DOCKER_HUB/$image:${tags_array[TAG]} exists.."		
		fi		
	 done
done

########### BEGING TAKING SNs LOGS######################
#Looping through all tags and collecting logs. 
#Only active container will have logs.
isSNExist=0 # To check whether SN container exists 
for TAG in "${!TAGS[@]}"
do
	SNs=$(docker ps -a -q  --filter ancestor=$DOCKER_HUB/sn:${tags_array[TAG]})
	sns_array=($SNs)
	for index in "${!sns_array[@]}"
	do
		docker logs ${sns_array[index]} > "$LOG_DIR"/sn_${tags_array[TAG]}_$index.log 
		docker inspect ${sns_array[index]} > "$LOG_DIR"/sn_inspect_${tags_array[TAG]}_$index.log
		isSNExist=1
	done
done

if [ "$isSNExist" == 0 ] ; then
    echo `date`"-ERROR: No active SN container exists in this host!!"
fi
########### END TAKING SNs LOGS######################

########### BEGIN TAKING SWOPs LOGS######################
isSWOPExist=0 # To check whether SWOP container exists 
for TAG in "${!TAGS[@]}"
do
	SWOPs=$(docker ps -a -q  --filter ancestor=$DOCKER_HUB/swop:${tags_array[TAG]})
	swops_array=($SWOPs)
	for index in "${!swops_array[@]}"
	do
		docker logs ${swops_array[index]}  > "$LOG_DIR"/swop_${tags_array[TAG]}_$index.log
		docker inspect ${swops_array[index]} > "$LOG_DIR"/swop_inspect_${tags_array[TAG]}_$index.log
		isSWOPExist=1
	done
done
if [ "$isSWOPExist" == 0 ] ; then
    echo `date`"-ERROR: No active SWOP container exists in this host!!"
fi
########### END TAKING SWOPs LOGS######################

########### BEGIN TAKING SLs LOGS######################
isSLExist=0 # To check whether SL container exists 
for TAG in "${!TAGS[@]}"
do
	SLs=$(docker ps -a -q  --filter ancestor=$DOCKER_HUB/sl:${tags_array[TAG]})
	sls_array=($SLs)
	for index in "${!sls_array[@]}"
	do
		docker logs ${sls_array[index]}  > "$LOG_DIR"/sl_${tags_array[TAG]}_$index.log 
		docker inspect ${sls_array[index]} > "$LOG_DIR"/sl_inspect_${tags_array[TAG]}_$index.log
		isSLExist=1
	done
done
if [ "$isSLExist" == 0 ] ; then
    echo `date`"-ERROR: No active SL container exists in this host!!"
fi
########### TAKING SNs LOGS######################

########### BEGIN TAKING USER LOGS######################
isMLExist=0 # To check whether ML container exists 
for TAG in "${!TAGS[@]}"
do
	MLs=$(docker ps -a -q  --filter ancestor=$USER_CONTAINERS)
	mls_array=($MLs)
	for index in "${!mls_array[@]}"
	do
		echo "INFO: capturing log for ${mls_array[index]}"
		docker logs ${mls_array[index]}  > "$LOG_DIR"/user_$index.log
		docker inspect ${mls_array[index]} > "$LOG_DIR"/ml_inspect_$index.log
		isMLExist=1
	done
done
if [ "$isMLExist" == 0 ] ; then
    echo `date`"-ERROR: No active ML container exists in this host!!"
fi
########### END TAKING USER LOGS######################

echo -e "Python Libraries:\n"
pip list

#cp out.log  "$LOG_DIR"/out.log
tar -czvf "$LOG_DIR.tar.gz" "$LOG_DIR"

echo `date`":LOG COLLECTION DONE"
echo "============================================="
