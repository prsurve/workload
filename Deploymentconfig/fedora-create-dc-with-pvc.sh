#!/bin/bash

### $1 is name storageclass that will be used to create pvc
### $2 is No of dc pods
### eg. sh fedora-create-dc-with-pvc.sh sc_name 2 project_name
### project_name is optional


sc_name=$1
no_of_pods=$2
if [ -z "$sc_name" ]
then
	printf "You need to pass storageclass Name\n"
	exit 1
fi
if [ -z "$no_of_pods" ]
then
      printf "You need to pass No of required Pod\n"
      exit 1
fi
verify_output ()
{
	if [ $? -eq 0 ]
	then
	  printf "\nCommand Executed successfully"
	else
	  printf "\nCommand Failed:- $OUTPUT" >&2
	  exit 1
	fi	
}

pvc_type[0]="ReadWriteOnce"
pvc_type[1]="ReadWriteMany"

mount_type[0]="volumeMounts:
        - mountPath: /mnt
          name: fedora-vol"
mount_type[1]="volumeDevices:
        - devicePath: /dev/rbdblock
          name: fedora-vol"
create_pvc ()
{
echo "kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $pvc_name
  namespace: $project_name
spec:
  accessModes:
    - $selected_mode
  $if_block_mode
  resources:
    requests:
      storage: 5Gi
  storageClassName: $sc_name" | oc create --recursive=true -f -
}

create_fedora_pod ()
{
echo "kind: DeploymentConfig
apiVersion: apps.openshift.io/v1
metadata:
  name: ${FEDORA_POD_LIST[$index]}
  namespace: $project_name
  labels:
    app: ${FEDORA_POD_LIST[$index]}
spec:
  template:
    metadata:
      labels:
        name: ${FEDORA_POD_LIST[$index]}
    spec:
      securityContext:
        fsGroup: 2000
      serviceAccountName: $service_account
      restartPolicy: Always
      volumes:
      - name: fedora-vol
        persistentVolumeClaim:
          claimName: $pvc_name
      containers:
      - name: fedora
        image: fedora
        resources:
          limits:
            memory: "800Mi"
            cpu: "150m"
        command: ['/bin/bash', '-ce', 'tail -f /dev/null']
        imagePullPolicy: IfNotPresent
        $selected_mount_mode
        livenessProbe:
          exec:
            command:
            - 'sh'
            - '-ec'
            - 'df /mnt'
          initialDelaySeconds: 3
          periodSeconds: 3

  replicas: 1
  triggers:
    - type: ConfigChange
  paused: false" | oc create --recursive=true -f -
}


check_status_pvc ()
{
	for i in {1..20}
	do
		status=$(oc get pvc $pvc_name -n $project_name -o custom-columns=:.status.phase |tr -d '\n' 2>&1)

		if [ $status == "Bound" ]
		then
			printf "PVC got bound successfully\n"
			break
		else
			printf "PVC failed to reach bound State\n"
		fi
		sleep 2
	done
}

check_pod_status ()
{
	for index in "${FEDORA_POD_LIST[@]}"
	do
		for cnt in {1..30}
		do	
			status=$(oc get pod -n $project_name --selector=name=$index -o custom-columns=:.status.phase |tr -d '\n')

			if [[ $status == "Running" ]]
			then
				printf "\n\nPod $index reached Running State\n\n"
				break
			else				
				COUNT=$(expr 60 - $cnt)
				printf "Retry left $COUNT..."
				printf "Retrying After 5 sec..\n"
				if [ $COUNT == "0" ]
				then
					printf "Pod $index Failed to reached Running State\n"
				fi				
			fi
			sleep 5
		done
		
	done
}

if [ -z "$3" ]
then
	project_name=namespace-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
	printf "\nCreated new Project with name $project_name" 
	OUTPUT=$(oc new-project $project_name 2>&1)
	verify_output $OUTPUT
else
	project_name=$3
	printf "\nUsing $project_name for creation"
fi

service_account=sa-name-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
printf "\nCreating serviceaccount with name $service_account"
OUTPUT=$(oc create serviceaccount $service_account -n $project_name 2>&1)

verify_output $OUTPUT

printf "\nAdding Serviceaccount to SCC/privileged"

OUTPUT=$(oc adm policy add-scc-to-user privileged system:serviceaccount:$project_name:$service_account 2>&1)

verify_output $OUTPUT

provisioner=$(oc get sc $sc_name -o custom-columns=:.provisioner|tr -d '\n'|cut -d '.' -f2 2>&1)
if [[ $provisioner == "cephfs" ]]
then
	selected_mount_mode=${mount_type[0]}
fi
for index in $(seq 1 $no_of_pods)
do
	selected_mode=${pvc_type[$RANDOM % ${#pvc_type[@]} ]}
	if [[ $selected_mode == "ReadWriteOnce" ]]
	then
		mode="rwo"
	elif [[ $selected_mode == "ReadWriteMany" ]]
	then
		mode="rwx"
	fi
	if [[ $provisioner == "rbd" ]]
	then
		if [[ $mode == "rwx" ]]
		then
			if_block_mode="volumeMode: Block"
			selected_mount_mode=${mount_type[1]}
		else
			selected_mount_mode=${mount_type[0]}
		fi
	fi	
	pvc_name=pvc-$provisioner-$mode-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	
	printf "\nCreating pvc with name $pvc_name and accessModes is $mode \n"
	create_pvc 
	check_status_pvc
	
	FEDORA_POD_LIST[$index]=fedorapod-$provisioner-$mode-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 5 | head -n 1)
	printf "\nCreating Pod with name ${FEDORA_POD_LIST[$index]}\n"
	create_fedora_pod
	unset if_block_mode
done

printf "\nChecking Status of pod\n"
check_pod_status $FEDORA_POD_LIST
